#!/usr/bin/env python3
# voice-dictation —— 按 F8 开始听，再按 F8 结束：识别、整理、贴进焦点窗口。F9 贴原文。
#
# 为什么是这几样（Qwen3-ASR、按停顿切段、Qwen3.5-9B、Shift+Insert）、
# 实测数据、和 VOICE_DICTATION.md 原方案的差异，见 Lesson-Learn/0019_VOICE_DICTATION.md。
#
# 只用标准库。外部程序的路径、模型清单、提示词都从环境变量
# VOICE_DICTATION_CONFIG 指向的 JSON 读（由 home/voice-dictation.nix 生成），
# 这里不写死任何 /nix/store 路径，所以构建期测试可以换一份假的 config。
#
# 状态全靠两个 pid 文件判断，放在 $XDG_RUNTIME_DIR/voice-dictation/（tmpfs，
# 重新登录就清空，不会留下过期状态）：
#   record.pid   存在且进程活着  -> 正在听
#   process.pid  存在且进程活着  -> 正在识别 / 整理
#   都没有                        -> 空闲
# 每一次录音（take）放在 ~/.cache/voice-dictation/takes/<时间>/：
#   audio.wav  raw.txt（原文）  clean.txt（整理稿）  log.txt  *-server.log

import base64
import contextlib
import fcntl
import hashlib
import http.client
import io
import json
import os
import re
import shutil
import signal
import socket
import subprocess
import sys
import time
import wave
from pathlib import Path

CFG = json.loads(Path(os.environ["VOICE_DICTATION_CONFIG"]).read_text())
BIN = CFG["bins"]

CACHE = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "voice-dictation"
MODELS = CACHE / "models"
TAKES = CACHE / "takes"
RUN = Path(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}") / "voice-dictation"

REC_PID = RUN / "record.pid"
PROC_PID = RUN / "process.pid"
CURRENT = RUN / "take"
WANT_RAW = RUN / "want-raw"
NOTIFY_ID = RUN / "notify-id"
LOCK = RUN / "lock"

DEVNULL = subprocess.DEVNULL


class PipelineError(Exception):
    def __init__(self, title, body=""):
        super().__init__(title)
        self.title = title
        self.body = body


def log(msg):
    print(time.strftime("%H:%M:%S ") + msg, file=sys.stderr, flush=True)


def tail(path, n=600):
    try:
        data = Path(path).read_bytes()[-n:]
    except OSError:
        return ""
    return data.decode("utf-8", "replace").strip()


# ---------------------------------------------------------------- 进程与状态


def read_pid(path, marker):
    """pid 文件里的进程还活着、而且确实是我们的那个（防 pid 复用），才返回 pid。"""
    try:
        pid = int(path.read_text().strip())
        cmdline = Path(f"/proc/{pid}/cmdline").read_bytes()
        state = Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()[0]
    except (OSError, ValueError, IndexError):
        return None
    if marker.encode() not in cmdline or state == "Z":
        return None
    return pid


def wait_gone(pid, timeout):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        try:
            state = Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()[0]
        except (OSError, IndexError):
            return True
        if state == "Z":
            return True
        time.sleep(0.02)
    return False


@contextlib.contextmanager
def locked():
    """F8、F9 和后台流程改状态之前都先拿这把锁，连按两下也不会起两个录音。"""
    RUN.mkdir(parents=True, exist_ok=True, mode=0o700)
    with open(LOCK, "w") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        yield


def current_take():
    try:
        take = Path(CURRENT.read_text().strip())
    except OSError:
        return None
    return take if take.is_dir() else None


def new_take_dir():
    TAKES.mkdir(parents=True, exist_ok=True)
    base = time.strftime("%Y%m%d-%H%M%S")
    take, n = TAKES / base, 2
    while take.exists():
        take, n = TAKES / f"{base}-{n}", n + 1
    take.mkdir()
    return take


def prune_takes():
    keep = CFG["keep_takes"]
    cur = current_take()
    dirs = sorted(p for p in TAKES.glob("*") if p.is_dir()) if TAKES.is_dir() else []
    for p in dirs[:-keep] if len(dirs) > keep else []:
        if p != cur:
            shutil.rmtree(p, ignore_errors=True)


def spawn_self(*args, logfile):
    with open(logfile, "ab") as lf:
        return subprocess.Popen(
            [sys.executable, "-I", os.path.abspath(__file__), *args],
            stdin=DEVNULL,
            stdout=lf,
            stderr=lf,
            start_new_session=True,
        )


# ---------------------------------------------------------------- 通知


def _gdbus(method, *args):
    return subprocess.run(
        [
            BIN["gdbus"], "call", "--session",
            "--dest", "org.freedesktop.Notifications",
            "--object-path", "/org/freedesktop/Notifications",
            "--method", f"org.freedesktop.Notifications.{method}", *args,
        ],
        capture_output=True, text=True, timeout=5,
    ).stdout


def notify(summary, body="", sticky=True):
    """sticky：critical + transient，一直留在屏幕上直到被替换或撤掉（正在听 / 正在整理）。
    非 sticky：普通通知，几秒后收进通知列表，用于报错。"""
    rid = 0
    with contextlib.suppress(OSError, ValueError):
        rid = int(NOTIFY_ID.read_text())
    hints = "{'urgency': <byte 2>, 'transient': <true>}" if sticky else "{'urgency': <byte 1>}"
    try:
        out = _gdbus(
            "Notify", "语音输入", str(rid), "audio-input-microphone-symbolic",
            summary, body, "[]", hints, "-1",
        )
    except (OSError, subprocess.SubprocessError):
        return
    m = re.search(r"uint32 (\d+)", out)
    if m and sticky:
        NOTIFY_ID.write_text(m.group(1))


def unnotify():
    try:
        rid = NOTIFY_ID.read_text().strip()
    except OSError:
        return
    NOTIFY_ID.unlink(missing_ok=True)
    with contextlib.suppress(OSError, subprocess.SubprocessError):
        _gdbus("CloseNotification", rid)


def notify_error(title, body=""):
    # 先撤掉 critical 的那条再发新的：critical 横幅被普通通知替换时不一定会自己收起。
    unnotify()
    notify(title, body, sticky=False)


# ---------------------------------------------------------------- 模型


def model_path(key):
    return MODELS / CFG["models"][key]["file"]


def stamp_path(key):
    f = model_path(key)
    return f.with_name(f.name + ".sha256")


def model_ok(key):
    """快速检查：大小对、而且 voice-dictation-models 校验通过后留下的戳记对得上。
    F8 每次都查，所以这里不算 sha256（8 GB 要十几秒）。"""
    m = CFG["models"][key]
    try:
        return (
            model_path(key).stat().st_size == m["size"]
            and stamp_path(key).read_text().strip() == m["sha256"]
        )
    except OSError:
        return False


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while chunk := f.read(1 << 22):
            h.update(chunk)
    return h.hexdigest()


def cmd_models(argv):
    verify = "--verify" in argv
    MODELS.mkdir(parents=True, exist_ok=True)
    bad = 0
    for key, m in CFG["models"].items():
        f, stamp = model_path(key), stamp_path(key)
        part = f.with_name(f.name + ".part")
        if model_ok(key) and not verify:
            print(f"ok    {m['file']}")
            continue
        if f.exists() and f.stat().st_size == m["size"]:
            print(f"校验  {m['file']}")
            if sha256(f) == m["sha256"]:
                stamp.write_text(m["sha256"] + "\n")
                print(f"ok    {m['file']}")
                continue
            print(f"      sha256 不对，删掉重下：{m['file']}")
            f.unlink()
        stamp.unlink(missing_ok=True)
        if not (part.exists() and part.stat().st_size == m["size"]):
            print(f"下载  {m['file']}（{m['size'] / 1e9:.2f} GB）")
            r = subprocess.run(
                [
                    BIN["curl"], "-fL", "-C", "-", "--retry", "8", "--retry-delay", "2",
                    "--retry-all-errors", "-o", str(part), m["url"],
                ]
            )
            if r.returncode != 0:
                print(f"      下载中断（curl 退出码 {r.returncode}）。再运行一次会接着下。")
                bad += 1
                continue
        if sha256(part) != m["sha256"]:
            part.unlink()
            print(f"      sha256 不对，已删掉下载的文件：{m['file']}")
            bad += 1
            continue
        part.rename(f)
        stamp.write_text(m["sha256"] + "\n")
        print(f"ok    {m['file']}")
    if bad:
        sys.exit(1)
    print(f"模型都在 {MODELS}")


def prewarm():
    """F8 开始听的时候，让内核把模型文件读进页缓存。开机后第一次用时
    不用等磁盘。只是 fadvise，不占显存，不加载模型。"""
    for key in ("asr", "asr_mmproj", "llm"):
        with contextlib.suppress(OSError):
            fd = os.open(model_path(key), os.O_RDONLY)
            try:
                os.posix_fadvise(fd, 0, 0, os.POSIX_FADV_WILLNEED)
            finally:
                os.close(fd)


# ---------------------------------------------------------------- 录音


def start_recording():
    take = new_take_dir()
    CURRENT.write_text(str(take))
    WANT_RAW.unlink(missing_ok=True)
    wav = take / "audio.wav"
    with open(take / "record.log", "ab") as lf:
        p = subprocess.Popen(
            [BIN["pw_record"], "--rate", "16000", "--channels", "1", "--format", "s16", str(wav)],
            stdin=DEVNULL, stdout=lf, stderr=lf, start_new_session=True,
        )
    REC_PID.write_text(str(p.pid))
    # pw-record 起流要 0.3 秒左右。等它真的开始写数据再报「正在听」，
    # 否则看到通知马上开口，第一个字会被吞掉。
    end = time.monotonic() + 3
    while time.monotonic() < end and p.poll() is None:
        with contextlib.suppress(OSError):
            if wav.stat().st_size > 44 + 1600:
                break
        time.sleep(0.02)
    if p.poll() is not None:
        REC_PID.unlink(missing_ok=True)
        notify_error("录音没有启动", tail(take / "record.log"))
        return
    notify("正在听", "再按 F8 结束并整理，F9 结束并贴原文")
    spawn_self("_prewarm", logfile=take / "log.txt")


def stop_recording(pid):
    with contextlib.suppress(ProcessLookupError):
        os.kill(pid, signal.SIGINT)
        if not wait_gone(pid, 3):
            os.kill(pid, signal.SIGTERM)
            if not wait_gone(pid, 2):
                os.kill(pid, signal.SIGKILL)
                wait_gone(pid, 2)
    REC_PID.unlink(missing_ok=True)


def start_processing(take):
    notify("正在识别")
    p = spawn_self("_process", str(take), logfile=take / "log.txt")
    PROC_PID.write_text(str(p.pid))


# ---------------------------------------------------------------- 人声检测与切段


def wav_duration(path):
    with wave.open(str(path)) as w:
        return w.getnframes() / w.getframerate()


def _split_long(group, max_s):
    """一段太长时，在它内部最长的停顿处切开，递归到每段都不超过 max_s。"""
    s, e, subs = group
    if e - s <= max_s or len(subs) < 2:
        return [group]
    gaps = [(subs[i + 1][0] - subs[i][1], i) for i in range(len(subs) - 1)]
    _, i = max(gaps)
    left, right = subs[: i + 1], subs[i + 1 :]
    return _split_long([left[0][0], left[-1][1], left], max_s) + _split_long(
        [right[0][0], right[-1][1], right], max_s
    )


def vad_groups(wav):
    """返回要分别送去识别的时间段 [(start, end), ...]（秒）。

    为什么要切：Qwen3-ASR 开口先给整段判一个语言，后面的识别都跟着它走。
    一段里中文、日语、英语各说一句时，实测会出现整段被当成英语、
    中文被译成英语、日语整句丢掉（Lesson-Learn/0019）。他换语言大多发生在
    停顿处，所以在停顿（>= min_gap_s）处切开，每段各自判语言。
    句子里夹的英文词不受影响：同一段里的混说模型本来就处理得好。"""
    v = CFG["vad"]
    r = subprocess.run(
        [
            BIN["vad"], "-vm", str(model_path("vad")), "-f", str(wav), "-np", "-t", "4",
            "-vt", str(v["threshold"]),
        ],
        capture_output=True, text=True, timeout=120,
    )
    if r.returncode != 0:
        raise PipelineError("人声检测失败", (r.stderr or r.stdout)[-400:])
    # whisper-vad-speech-segments 打印的单位是 1/100 秒
    segs = [
        (float(a) / 100, float(b) / 100)
        for a, b in re.findall(r"start = ([\d.]+), end = ([\d.]+)", r.stdout)
    ]
    groups = []
    for s, e in segs:
        if groups and s - groups[-1][1] < v["min_gap_s"]:
            groups[-1][1] = max(groups[-1][1], e)
            groups[-1][2].append((s, e))
        else:
            groups.append([s, e, [(s, e)]])
    # 太短的一段（单独一个「嗯」「OK」）判语言不稳，并进后一段（最后一段就并进前一段）。
    i = 0
    while len(groups) > 1 and i < len(groups):
        if groups[i][1] - groups[i][0] >= v["min_group_s"]:
            i += 1
            continue
        a, b = (i, i + 1) if i + 1 < len(groups) else (i - 1, i)
        groups[a : b + 1] = [[groups[a][0], groups[b][1], groups[a][2] + groups[b][2]]]
        i = 0
    out = []
    for g in groups:
        out += _split_long(g, v["max_group_s"])
    dur = wav_duration(wav)
    pad = v["pad_s"]
    return [(max(0.0, s - pad), min(dur, e + pad)) for s, e, _ in out]


def wav_slice_b64(path, start, end):
    with wave.open(str(path)) as w:
        rate, width, ch = w.getframerate(), w.getsampwidth(), w.getnchannels()
        w.setpos(int(start * rate))
        frames = w.readframes(int((end - start) * rate))
    buf = io.BytesIO()
    with wave.open(buf, "wb") as o:
        o.setnchannels(ch)
        o.setsampwidth(width)
        o.setframerate(rate)
        o.writeframes(frames)
    return base64.b64encode(buf.getvalue()).decode()


# ---------------------------------------------------------------- llama-server


class UnixHTTPConnection(http.client.HTTPConnection):
    def __init__(self, path, timeout):
        super().__init__("localhost", timeout=timeout)
        self._path = str(path)

    def connect(self):
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(self.timeout)
        s.connect(self._path)
        self.sock = s


def http_json(sock, method, path, body=None, timeout=10):
    c = UnixHTTPConnection(sock, timeout)
    try:
        data = json.dumps(body).encode() if body is not None else None
        c.request(method, path, body=data, headers={"Content-Type": "application/json"})
        r = c.getresponse()
        return r.status, r.read()
    finally:
        c.close()


def _vram_problem(logpath):
    return bool(
        re.search(
            r"out of memory|cudaMalloc failed|failed to allocate|unable to allocate",
            tail(logpath, 6000), re.I,
        )
    )


@contextlib.contextmanager
def llama_server(args, sock, logpath, child, what):
    """起一个只听 unix socket 的 llama-server，用完就停，显存当场还回去。

    每次现起现停而不是常驻：听的时候不占显存，Qwen3-TTS 之类别的 GPU 程序
    只会在第二次 F8 之后的几秒里和它碰上；独显也能在两次之间睡下去。
    --fit 默认开着：显存被别人占了一部分时，它会把放不下的层留在内存里，
    变慢而不是直接失败。"""
    sock.unlink(missing_ok=True)
    with open(logpath, "ab") as lf:
        p = subprocess.Popen(
            [BIN["llama_server"], *args, "--host", str(sock), "--no-webui", "-np", "1"],
            stdin=DEVNULL, stdout=lf, stderr=lf,
        )
    child["p"] = p
    try:
        end = time.monotonic() + CFG["load_timeout_s"]
        while True:
            if p.poll() is not None:
                raise PipelineError(
                    "显存不够" if _vram_problem(logpath) else f"{what}模型没能加载",
                    tail(logpath, 300),
                )
            if time.monotonic() > end:
                raise PipelineError(f"{what}模型加载超时")
            with contextlib.suppress(OSError, http.client.HTTPException):
                if http_json(sock, "GET", "/health", timeout=2)[0] == 200:
                    break
            time.sleep(0.05)
        yield
    finally:
        if p.poll() is None:
            p.terminate()
            try:
                p.wait(5)
            except subprocess.TimeoutExpired:
                p.kill()
                p.wait()
        child["p"] = None
        sock.unlink(missing_ok=True)


def chat(sock, body, timeout, what, logpath):
    try:
        status, data = http_json(sock, "POST", "/v1/chat/completions", body, timeout=timeout)
    except (OSError, http.client.HTTPException) as e:
        raise PipelineError("显存不够" if _vram_problem(logpath) else f"{what}没有完成", str(e))
    if status != 200:
        raise PipelineError(
            "显存不够" if _vram_problem(logpath) else f"{what}出错（HTTP {status}）",
            data.decode("utf-8", "replace")[:300],
        )
    return json.loads(data)["choices"][0]["message"]["content"] or ""


# ---------------------------------------------------------------- 识别


ASCII_SENTENCE_END = set(".,!?;:")
CJK_CLOSE = set("。，、？！：；」』）】…")


def join_parts(parts):
    """把各段的识别结果接起来。英文和英文之间补空格，中日文之间不加。"""
    out = ""
    for p in (x.strip() for x in parts):
        if not p:
            continue
        if out:
            a, b = out[-1], p[0]
            if (a.isascii() and not a.isspace()) or (b.isascii() and b.isalnum() and a not in CJK_CLOSE):
                out += " "
        out += p
    return out


def parse_asr(text):
    # Qwen3-ASR 的输出形如「language Chinese<asr_text>识别出的文字」，没声音时是 language None。
    m = re.search(r"<asr_text>(.*)", text, re.S)
    return (m.group(1) if m else text).strip()


def transcribe(wav, groups, child, logdir):
    sock = RUN / "asr.sock"
    logpath = logdir / "asr-server.log"
    args = [
        "-m", str(model_path("asr")), "--mmproj", str(model_path("asr_mmproj")),
        "-c", "8192",
    ]
    parts = []
    with llama_server(args, sock, logpath, child, "识别"):
        for s, e in groups:
            body = {
                "messages": [
                    # Qwen3-ASR 把 system 当作「上下文」：列出专有名词能明显减少听错。
                    {"role": "system", "content": CFG["asr_context"]},
                    {
                        "role": "user",
                        "content": [
                            {
                                "type": "input_audio",
                                "input_audio": {"data": wav_slice_b64(wav, s, e), "format": "wav"},
                            }
                        ],
                    },
                ],
                "temperature": 0,
                "max_tokens": int((e - s) * 25) + 64,
            }
            t0 = time.monotonic()
            text = parse_asr(chat(sock, body, 60 + (e - s), "识别", logpath))
            log(f"asr {s:7.2f}-{e:7.2f}s {time.monotonic() - t0:5.2f}s  {text}")
            parts.append(text)
    return join_parts(parts)


# ---------------------------------------------------------------- 整理


def cleanup(raw, child, logdir):
    c = CFG["cleanup"]

    def wrap(t):
        return "<transcript>\n" + t + "\n</transcript>"

    msgs = [{"role": "system", "content": c["system"]}]
    for said, cleaned in c["shots"]:
        msgs += [{"role": "user", "content": wrap(said)}, {"role": "assistant", "content": cleaned}]
    msgs.append({"role": "user", "content": wrap(raw)})
    ctx = 8192 if len(raw) < 2000 else 32768
    args = ["-m", str(model_path("llm")), "-c", str(ctx), "--reasoning", "off"]
    sock = RUN / "llm.sock"
    logpath = logdir / "llm-server.log"
    with llama_server(args, sock, logpath, child, "整理"):
        body = {"messages": msgs, "temperature": 0, "max_tokens": 2 * len(raw) + 256}
        out = chat(sock, body, 60 + len(raw) / 10, "整理", logpath)
    out = re.sub(r"</?transcript>", "", out).strip()
    if not out:
        raise PipelineError("整理结果是空的")
    # 整理只删不加。比原话长出一大截，多半是模型把它当成提问去回答了。
    if len(out) > 1.6 * len(raw) + 30:
        raise PipelineError("整理结果不像原话", out[:200])
    return out


# ---------------------------------------------------------------- 粘贴


TEXT_TYPES = ("text/plain;charset=utf-8", "UTF8_STRING", "text/plain")
META_TYPES = {"TARGETS", "TIMESTAMP", "MULTIPLE", "SAVE_TARGETS"}


def _sel(primary):
    return ["--primary"] if primary else []


def grab(primary):
    """记下剪贴板现在的内容（类型 + 字节）。空的返回 None，之后清空即可。"""
    try:
        r = subprocess.run(
            [BIN["wl_paste"], *_sel(primary), "--list-types"], capture_output=True, timeout=2
        )
        if r.returncode != 0:
            return None
        types = [t for t in r.stdout.decode().splitlines() if t and t not in META_TYPES]
        if not types:
            return None
        t = next((x for x in TEXT_TYPES if x in types), None)
        t = t or next((x for x in types if x.startswith("image/")), types[0])
        d = subprocess.run(
            [BIN["wl_paste"], *_sel(primary), "--no-newline", "--type", t],
            capture_output=True, timeout=3,
        )
        return (t, d.stdout) if d.returncode == 0 else None
    except (OSError, subprocess.SubprocessError):
        return None


def put(primary, saved):
    # wl-copy 会 fork 出一个常驻进程提供剪贴板内容，它会继承 stdout/stderr。
    # 必须接到 DEVNULL：接到管道的话 subprocess.run 会一直等管道关闭。
    if saved is None:
        cmd, data = [BIN["wl_copy"], *_sel(primary), "--clear"], b""
    else:
        cmd, data = [BIN["wl_copy"], *_sel(primary), "--type", saved[0]], saved[1]
    with contextlib.suppress(OSError, subprocess.SubprocessError):
        subprocess.run(cmd, input=data, stdout=DEVNULL, stderr=DEVNULL, timeout=3)


def paste(text):
    """文字走剪贴板，ydotool 只按 Shift+Insert，不送任何字符。

    为什么是 Shift+Insert：GNOME Wayland 上普通程序查不到焦点窗口是谁，
    没法给 Ghostty 发 Ctrl+Shift+V、给别处发 Ctrl+V。Shift+Insert 在
    浏览器、VS Code、GTK/Qt 程序里是「从剪贴板粘贴」，在 Ghostty 里是
    「从 primary 选区粘贴」——两个选区都写成同一段文字，哪边都对。
    evdev 键码和键盘布局无关（Ctrl+V 的 V 在别的布局下会变）。"""
    text = text.rstrip("\n")
    data = text.encode()
    old, old_primary = grab(False), grab(True)
    put(False, ("text/plain;charset=utf-8", data))
    put(True, ("text/plain;charset=utf-8", data))
    env = dict(os.environ, YDOTOOL_SOCKET=CFG["ydotool_socket"])
    try:
        r = subprocess.run(
            [BIN["ydotool"], "key", "42:1", "110:1", "110:0", "42:0"],
            env=env, capture_output=True, timeout=5,
        )
        ok = r.returncode == 0
    except (OSError, subprocess.SubprocessError):
        ok = False
    if not ok:
        # 文字留在剪贴板里，不恢复，让人能手动贴。
        notify_error(
            "没能自动粘贴，文字在剪贴板里",
            "按 Ctrl+V 粘贴（终端里 Ctrl+Shift+V）。刚 switch 过的话，先注销再登录一次。",
        )
        return False
    # 等目标程序把剪贴板读走再换回去。Ghostty 里偶尔贴丢的话只调大这个值。
    time.sleep(CFG["paste_delay_ms"] / 1000)
    put(False, old)
    put(True, old_primary)
    return True


def paste_and_finish(text):
    if paste(text):
        unnotify()


# ---------------------------------------------------------------- 后台流程


def run_pipeline(take, child):
    wav = take / "audio.wav"
    t0 = time.monotonic()
    groups = vad_groups(wav)
    (take / "segments.json").write_text(json.dumps(groups))
    log(f"vad: {len(groups)} 段，{wav_duration(wav):.1f}s 录音")
    if not groups:
        notify_error("没听到说话")
        return
    try:
        raw = transcribe(wav, groups, child, take)
    except PipelineError as e:
        notify_error(f"识别失败：{e.title}", (e.body + "\n录音还在，可以运行 voice-dictation retry").strip())
        return
    (take / "raw.txt").write_text(raw + "\n")
    log(f"raw ({time.monotonic() - t0:.1f}s): {raw}")
    if not raw:
        notify_error("没识别出文字")
        return
    if WANT_RAW.exists():
        with locked():
            paste_and_finish(raw)
        return
    notify("正在整理")
    try:
        clean = cleanup(raw, child, take)
    except PipelineError as e:
        log(f"cleanup failed: {e.title} {e.body}")
        notify_error(f"{e.title}，原文已留下", "按 F9 贴原文")
        return
    (take / "clean.txt").write_text(clean + "\n")
    log(f"clean ({time.monotonic() - t0:.1f}s): {clean}")
    with locked():
        paste_and_finish(raw if WANT_RAW.exists() else clean)


def cmd_process(take):
    take = Path(take)
    child = {"p": None}

    def on_term(_sig, _frame):
        p = child["p"]
        if p is not None and p.poll() is None:
            p.terminate()
        sys.exit(143)

    signal.signal(signal.SIGTERM, on_term)
    signal.signal(signal.SIGINT, signal.SIG_IGN)
    try:
        run_pipeline(take, child)
    except PipelineError as e:
        notify_error(e.title, e.body)
    except Exception as e:  # 后台进程没人看着，任何异常都要变成一条通知
        log(f"unexpected: {e!r}")
        notify_error("语音输入出错", repr(e)[:300])
        raise
    finally:
        if read_pid(PROC_PID, "_process") == os.getpid():
            PROC_PID.unlink(missing_ok=True)
        prune_takes()


# ---------------------------------------------------------------- 按键入口


def cmd_toggle():
    """F8。空闲 -> 开始听；正在听 -> 结束，识别 + 整理后贴整理稿；正在整理 -> 忽略。"""
    with locked():
        pid = read_pid(REC_PID, "pw-record")
        if pid:
            stop_recording(pid)
            start_processing(current_take())
            return
        if read_pid(PROC_PID, "_process"):
            return
        if not all(model_ok(k) for k in CFG["models"]):
            notify_error("模型还没下载", "先在终端运行 voice-dictation-models")
            return
        start_recording()


def cmd_raw():
    """F9。意思始终是「这一段我要原文」：
    正在听   -> 结束录音，识别完直接贴原文，不整理（准备好的短指令走这条最快）
    正在识别 -> 识别完贴原文，不整理
    正在整理 -> 停掉整理，马上贴原文
    空闲     -> 贴上一段的原文（整理改坏了的时候用）"""
    with locked():
        pid = read_pid(REC_PID, "pw-record")
        if pid:
            WANT_RAW.touch()
            stop_recording(pid)
            start_processing(current_take())
            return
        take = current_take()
        raw = take / "raw.txt" if take else None
        ppid = read_pid(PROC_PID, "_process")
        if ppid:
            WANT_RAW.touch()
            if raw and raw.exists():
                with contextlib.suppress(ProcessLookupError):
                    os.killpg(ppid, signal.SIGTERM)
                wait_gone(ppid, 5)
                PROC_PID.unlink(missing_ok=True)
                paste_and_finish(raw.read_text())
            return
        if raw and raw.exists():
            paste(raw.read_text())


def cmd_retry():
    with locked():
        if read_pid(REC_PID, "pw-record") or read_pid(PROC_PID, "_process"):
            print("正在听或正在处理，稍后再试", file=sys.stderr)
            sys.exit(1)
        take = current_take()
        if not take or not (take / "audio.wav").exists():
            print("没有可以重试的录音", file=sys.stderr)
            sys.exit(1)
        WANT_RAW.unlink(missing_ok=True)
        start_processing(take)
    print(f"重新处理 {take}")


def cmd_status():
    if read_pid(REC_PID, "pw-record"):
        state = "正在听"
    elif read_pid(PROC_PID, "_process"):
        state = "正在识别 / 整理"
    else:
        state = "空闲"
    print(f"状态    {state}")
    for key, m in CFG["models"].items():
        print(f"模型    {'ok     ' if model_ok(key) else '缺/未校验'} {m['file']}")
    take = current_take()
    print(f"这一段  {take or '-'}")
    if take:
        for name in ("raw.txt", "clean.txt"):
            if (take / name).exists():
                print(f"  {name:9} {(take / name).read_text().strip()}")
        print(tail(take / "log.txt", 1500))


def cmd_transcribe(argv):
    """调试用：对任意 wav 跑人声检测 + 识别，打印原文。会占显存。"""
    wav = Path(argv[0])
    with contextlib.ExitStack():
        logdir = Path(os.environ.get("TMPDIR", "/tmp"))
        groups = vad_groups(wav)
        for s, e in groups:
            print(f"# {s:.2f}-{e:.2f}s", file=sys.stderr)
        print(transcribe(wav, groups, {"p": None}, logdir))


def cmd_clean(argv):
    """调试用：对一段文字跑整理，打印结果。会占显存。"""
    logdir = Path(os.environ.get("TMPDIR", "/tmp"))
    print(cleanup(" ".join(argv), {"p": None}, logdir))


USAGE = """用法：voice-dictation <命令>
  toggle            F8：开始听 / 结束并整理
  raw               F9：贴原文（正在听时：结束并贴原文）
  status            看状态、模型和上一段的结果
  retry             重新处理上一段录音（识别失败之后用）
  models [--verify] 下载并校验模型（也可以直接运行 voice-dictation-models）
  transcribe <wav>  调试：只识别一个文件
  clean <文字>      调试：只整理一段文字"""


def main(argv):
    if not argv:
        print(USAGE)
        return
    cmd, rest = argv[0], argv[1:]
    RUN.mkdir(parents=True, exist_ok=True, mode=0o700)
    if cmd == "toggle":
        cmd_toggle()
    elif cmd == "raw":
        cmd_raw()
    elif cmd == "status":
        cmd_status()
    elif cmd == "retry":
        cmd_retry()
    elif cmd == "models":
        cmd_models(rest)
    elif cmd == "transcribe" and rest:
        cmd_transcribe(rest)
    elif cmd == "clean" and rest:
        cmd_clean(rest)
    elif cmd == "_process" and rest:
        cmd_process(rest[0])
    elif cmd == "_prewarm":
        prewarm()
    else:
        print(USAGE, file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main(sys.argv[1:])
