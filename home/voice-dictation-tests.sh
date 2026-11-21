#!/usr/bin/env bash
#
# voice-dictation 的回归测试（状态机）。
#
# 接缝是 **CLI 边界**：`voice-dictation toggle`（F8）和 `raw`（F9）。
# 外部程序全换成假的，放在临时目录里，由一份假的 config 指过去：
#   pw-record      把夹具 wav 拷到目标路径，然后一直等到被 SIGINT
#   whisper-vad    打印 $T/vad.out 的内容（人声段落）
#   llama-server   python 写的假服务器，听 unix socket：
#                  带音频的请求回 $T/asr.txt，纯文字的请求等 $T/llm.delay 秒后回 $T/llm.txt
#   wl-copy/paste  剪贴板是 $T/sel/ 下的两个文件，每次写入记一行日志
#   ydotool        只记参数
#   gdbus          只记通知的标题
# 断言的是**最终结果**：贴进去的是哪段文字、发了哪些通知、剪贴板有没有放回去、
# ydotool 收到的是不是只有键码。不测任何内部函数。
#
# 不碰 GPU、麦克风和真剪贴板。由 home/voice-dictation.nix 在**构建期**执行，
# 测试不过 nhm / nrb 就停在这。手动跑：
#   PYTHON=python3 VD_SCRIPT=home/voice-dictation.py bash home/voice-dictation-tests.sh

set -uo pipefail

PY="${PYTHON:?需要 PYTHON 指向 python3}"
SCRIPT="${VD_SCRIPT:?需要 VD_SCRIPT 指向 voice-dictation.py}"
BASH_BIN="$(command -v bash)"

fails=0
pass() { printf '  ok    %s\n' "$1"; }
fail() {
  printf '  FAIL  %s\n' "$1" >&2
  fails=$((fails + 1))
}

T="$(mktemp -d)"
export HOME="$T/home" XDG_CACHE_HOME="$T/cache" XDG_RUNTIME_DIR="$T/run"
mkdir -p "$HOME" "$XDG_CACHE_HOME" "$XDG_RUNTIME_DIR" "$T/bin" "$T/sel"
RUN="$XDG_RUNTIME_DIR/voice-dictation"
MODELS="$XDG_CACHE_HOME/voice-dictation/models"

# ---------------------------------------------------------------- 假程序

cat > "$T/bin/pw-record" <<EOF
#!$BASH_BIN
out="\${@: -1}"
cp "$T/fixture.wav" "\$out"
trap 'exit 1' INT TERM
while :; do sleep 0.05; done
EOF

cat > "$T/bin/whisper-vad" <<EOF
#!$BASH_BIN
cat "$T/vad.out"
EOF

cat > "$T/bin/wl-copy" <<EOF
#!$BASH_BIN
sel=clipboard
clear=0
for a in "\$@"; do
  case "\$a" in
    --primary) sel=primary ;;
    --clear) clear=1 ;;
  esac
done
if [ "\$clear" = 1 ]; then
  rm -f "$T/sel/\$sel"
  printf '%s <clear>\n' "\$sel" >> "$T/wl-copy.log"
else
  cat > "$T/sel/\$sel"
  printf '%s %s\n' "\$sel" "\$(cat "$T/sel/\$sel")" >> "$T/wl-copy.log"
fi
EOF

cat > "$T/bin/wl-paste" <<EOF
#!$BASH_BIN
sel=clipboard
list=0
for a in "\$@"; do
  case "\$a" in
    --primary) sel=primary ;;
    --list-types) list=1 ;;
  esac
done
[ -s "$T/sel/\$sel" ] || { echo "Nothing is copied" >&2; exit 1; }
if [ "\$list" = 1 ]; then echo "text/plain;charset=utf-8"; else cat "$T/sel/\$sel"; fi
EOF

cat > "$T/bin/ydotool" <<EOF
#!$BASH_BIN
printf '%s\n' "\$*" >> "$T/ydotool.log"
exit "\$(cat "$T/ydotool.exit" 2>/dev/null || echo 0)"
EOF

cat > "$T/bin/gdbus" <<EOF
#!$BASH_BIN
method=""
while [ \$# -gt 0 ]; do
  if [ "\$1" = --method ]; then method="\$2"; shift 2; break; fi
  shift
done
case "\$method" in
  *.Notify) printf 'notify %s\n' "\$4" >> "$T/notify.log"; echo "(uint32 7,)" ;;
  *.CloseNotification) printf 'close\n' >> "$T/notify.log"; echo "()" ;;
esac
EOF

cat > "$T/bin/llama-server.py" <<'EOF'
import json, os, signal, socketserver, sys, time
from http.server import BaseHTTPRequestHandler
T = os.environ["FAKE_T"]
args = sys.argv[1:]
sock = args[args.index("--host") + 1]
def logline(s):
    with open(os.path.join(T, "llama.log"), "a") as f:
        f.write(s + "\n")
class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass
    def _send(self, code, obj):
        data = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)
    def do_GET(self):
        self._send(200, {"status": "ok"})
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        last = body["messages"][-1]["content"]
        if isinstance(last, list):
            logline("asr")
            text = "language Chinese<asr_text>" + open(os.path.join(T, "asr.txt")).read().strip()
        else:
            logline("llm")
            time.sleep(float(open(os.path.join(T, "llm.delay")).read()))
            text = open(os.path.join(T, "llm.txt")).read().strip()
        self._send(200, {"choices": [{"message": {"content": text}}]})
class S(socketserver.UnixStreamServer):
    def get_request(self):
        req, _ = super().get_request()
        return req, ("local", 0)
signal.signal(signal.SIGTERM, lambda *a: (logline("stopped"), os._exit(0)))
logline("start " + ("asr" if "--mmproj" in args else "llm"))
S(sock, H).serve_forever()
EOF
cat > "$T/bin/llama-server" <<EOF
#!$BASH_BIN
export FAKE_T="$T"
exec "$PY" -I "$T/bin/llama-server.py" "\$@"
EOF

chmod +x "$T"/bin/*

# 2 秒静音的 16 kHz 单声道 wav
"$PY" -I -c '
import sys, wave
with wave.open(sys.argv[1], "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(16000)
    w.writeframes(b"\0\0" * 32000)
' "$T/fixture.wav"

# ---------------------------------------------------------------- 假 config

cat > "$T/config.json" <<EOF
{
  "bins": {
    "llama_server": "$T/bin/llama-server",
    "vad": "$T/bin/whisper-vad",
    "pw_record": "$T/bin/pw-record",
    "wl_copy": "$T/bin/wl-copy",
    "wl_paste": "$T/bin/wl-paste",
    "ydotool": "$T/bin/ydotool",
    "gdbus": "$T/bin/gdbus",
    "curl": "/nonexistent/curl"
  },
  "ydotool_socket": "$T/ydotool.sock",
  "models": {
    "asr": {"file": "asr.gguf", "size": 10, "sha256": "fake", "url": ""},
    "asr_mmproj": {"file": "mmproj.gguf", "size": 10, "sha256": "fake", "url": ""},
    "llm": {"file": "llm.gguf", "size": 10, "sha256": "fake", "url": ""},
    "vad": {"file": "vad.bin", "size": 10, "sha256": "fake", "url": ""}
  },
  "asr_context": "NixOS",
  "cleanup": {"system": "test", "shots": [["a", "b"]]},
  "vad": {"threshold": 0.5, "min_gap_s": 0.8, "min_group_s": 1.0, "max_group_s": 60, "pad_s": 0.2},
  "paste_delay_ms": 10,
  "keep_takes": 20,
  "load_timeout_s": 20
}
EOF
export VOICE_DICTATION_CONFIG="$T/config.json"

vd() { "$PY" -I "$SCRIPT" "$@"; }

# 等后台流程（process.pid）结束
wait_idle() {
  local i
  for i in $(seq 1 200); do
    [ -e "$RUN/process.pid" ] || return 0
    sleep 0.1
  done
  return 1
}

# 等这一段的原文写好
wait_raw() {
  local i take
  for i in $(seq 1 200); do
    take="$(cat "$RUN/take" 2>/dev/null)"
    [ -n "$take" ] && [ -s "$take/raw.txt" ] && return 0
    sleep 0.1
  done
  return 1
}

reset_logs() {
  rm -f "$T"/*.log
  printf 'ORIGINAL' > "$T/sel/clipboard"
  printf 'PRIMARY-OLD' > "$T/sel/primary"
  echo 0 > "$T/ydotool.exit"
}

# 贴进去的文字 = 写进剪贴板之后紧跟着 ydotool 按键的那一次。
# 假 wl-copy 每次写入记一行，按顺序是：clipboard <贴的字>、primary <贴的字>、
# 然后恢复成原来的内容。
pasted() { grep '^clipboard ' "$T/wl-copy.log" 2>/dev/null | sed -n 1p | cut -d' ' -f2-; }

echo 'speech segment 0: none' > "$T/vad.out"
printf '%s' '嗯，帮我跑一下测试。' > "$T/asr.txt"
printf '%s' '帮我跑一下测试。' > "$T/llm.txt"
echo 0 > "$T/llm.delay"
reset_logs

# ---------------------------------------------------------------- 用例

echo "== 模型不在缓存里：F8 只提示下载命令，不开始录音"
vd toggle
if grep -q '^notify 模型还没下载' "$T/notify.log" && [ ! -e "$RUN/record.pid" ]; then
  pass "提示 voice-dictation-models，没有录音"
else
  fail "缺模型时应提示下载且不录音"
fi

mkdir -p "$MODELS"
for f in asr.gguf mmproj.gguf llm.gguf vad.bin; do
  printf '0123456789' > "$MODELS/$f"
  echo fake > "$MODELS/$f.sha256"
done

echo "== F8 开始听，再按 F8：识别 -> 整理 -> 贴整理稿；整理中再按 F8 被忽略"
reset_logs
echo 'Speech segment 0: start = 10.00, end = 150.00' > "$T/vad.out"
echo 1.5 > "$T/llm.delay"
vd toggle
grep -q '^notify 正在听' "$T/notify.log" && pass "通知「正在听」" || fail "开始录音后应通知「正在听」"
[ -e "$RUN/record.pid" ] && pass "录音进程在跑" || fail "应有录音进程"
vd toggle
wait_raw || fail "等不到 raw.txt"
takes_before=$(ls "$XDG_CACHE_HOME/voice-dictation/takes" | wc -l)
vd toggle # 整理进行中（假 llm 要 1.5 秒）
takes_after=$(ls "$XDG_CACHE_HOME/voice-dictation/takes" | wc -l)
[ "$takes_before" = "$takes_after" ] && [ ! -e "$RUN/record.pid" ] &&
  pass "整理中按 F8 不开始新录音" || fail "整理中按 F8 应被忽略"
wait_idle || fail "后台流程没有结束"
[ "$(pasted)" = '帮我跑一下测试。' ] && pass "贴的是整理稿" || fail "应贴整理稿，实际：$(pasted)"
[ "$(cat "$T/sel/clipboard")" = 'ORIGINAL' ] && pass "剪贴板放回了原来的内容" || fail "剪贴板没有恢复：$(cat "$T/sel/clipboard")"
[ "$(cat "$T/sel/primary")" = 'PRIMARY-OLD' ] && pass "primary 选区也放回了" || fail "primary 没有恢复"
[ "$(cat "$T/ydotool.log")" = 'key 42:1 110:1 110:0 42:0' ] && pass "ydotool 只按了一次 Shift+Insert" || fail "ydotool 收到：$(cat "$T/ydotool.log")"
grep -q '^notify 正在识别' "$T/notify.log" && grep -q '^notify 正在整理' "$T/notify.log" &&
  pass "通知依次换成「正在识别」「正在整理」" || fail "缺少「正在识别」或「正在整理」"
[ "$(tail -1 "$T/notify.log")" = close ] && pass "成功后撤掉通知" || fail "成功后应撤掉通知"
[ "$(grep -c '^notify 正在听' "$T/notify.log")" = 1 ] && pass "整个过程只开始过一次录音" || fail "「正在听」出现了不止一次"
[ "$(grep -c '^stopped' "$T/llama.log")" = 2 ] && pass "识别和整理的服务器用完都停了" || fail "llama-server 没有都停掉：$(cat "$T/llama.log")"

echo "== 空闲时 F9：贴上一段的原文"
reset_logs
vd raw
[ "$(pasted)" = '嗯，帮我跑一下测试。' ] && pass "贴的是原文" || fail "F9 应贴原文，实际：$(pasted)"

echo "== 正在听时按 F9：结束录音，只识别不整理，贴原文"
reset_logs
echo 0 > "$T/llm.delay"
vd toggle
vd raw
wait_idle || fail "后台流程没有结束"
[ "$(pasted)" = '嗯，帮我跑一下测试。' ] && pass "贴的是原文" || fail "应贴原文，实际：$(pasted)"
grep -q '^llm' "$T/llama.log" && fail "不该调用整理模型" || pass "没有调用整理模型"

echo "== 整理中按 F9：停掉整理，马上贴原文，整理稿不会再贴"
reset_logs
echo 3 > "$T/llm.delay"
vd toggle
vd toggle
wait_raw || fail "等不到 raw.txt"
for i in $(seq 1 100); do grep -q '^llm' "$T/llama.log" 2>/dev/null && break; sleep 0.05; done
vd raw
wait_idle || fail "后台流程没有结束"
sleep 3.5
[ "$(grep -c '^clipboard 帮我跑一下测试。$' "$T/wl-copy.log")" = 0 ] && [ "$(pasted)" = '嗯，帮我跑一下测试。' ] &&
  pass "只贴了原文" || fail "应只贴原文：$(cat "$T/wl-copy.log")"
[ "$(grep -c '^key' "$T/ydotool.log")" = 1 ] && pass "只粘贴了一次" || fail "粘贴次数不对"
grep -q '^stopped' "$T/llama.log" && pass "整理服务器被停掉" || fail "整理服务器没有停"

echo "== 没说话：通知「没听到说话」，什么也不贴"
reset_logs
echo 'Detected 0 speech segments:' > "$T/vad.out"
vd toggle
vd toggle
wait_idle || fail "后台流程没有结束"
grep -q '^notify 没听到说话' "$T/notify.log" && pass "通知「没听到说话」" || fail "应通知「没听到说话」"
[ ! -s "$T/ydotool.log" ] && pass "没有粘贴" || fail "不该粘贴"
grep -q '^start' "$T/llama.log" 2>/dev/null && fail "没说话时不该加载模型" || pass "没有加载模型"

echo "== 整理结果比原话长出一大截：不贴，提示原文已留下，F9 能拿回原文"
reset_logs
echo 'Speech segment 0: start = 10.00, end = 150.00' > "$T/vad.out"
echo 0 > "$T/llm.delay"
printf '%s' '当然可以！跑测试的方法有很多种，首先你需要打开终端，然后输入 nix build，接着观察输出里有没有红色的报错信息，如果有的话就把它复制下来发给我。' > "$T/llm.txt"
vd toggle
vd toggle
wait_idle || fail "后台流程没有结束"
grep -q '原文已留下' "$T/notify.log" && pass "提示原文已留下" || fail "应提示原文已留下：$(cat "$T/notify.log")"
[ ! -s "$T/ydotool.log" ] && pass "可疑的整理稿没有贴" || fail "可疑的整理稿不该贴"
vd raw
[ "$(pasted)" = '嗯，帮我跑一下测试。' ] && pass "F9 贴原文" || fail "F9 应贴原文"
printf '%s' '帮我跑一下测试。' > "$T/llm.txt"

echo "== ydotool 失败（刚 switch、组还没生效）：提示手动粘贴，文字留在剪贴板"
reset_logs
echo 2 > "$T/ydotool.exit"
vd raw
grep -q '^notify 没能自动粘贴' "$T/notify.log" && pass "提示手动粘贴" || fail "应提示手动粘贴"
[ "$(cat "$T/sel/clipboard")" = '嗯，帮我跑一下测试。' ] && pass "文字留在剪贴板里" || fail "失败时不该把剪贴板换回去"

echo "== 任何时候 ydotool 都只收到键码，不收文字"
if [ -s "$T/ydotool.log" ] && ! grep -v -E '^key( [0-9]+:[01])+$' "$T/ydotool.log" >/dev/null; then
  pass "只有键码"
else
  fail "ydotool 收到了键码以外的东西：$(cat "$T/ydotool.log")"
fi

echo "== 连按两次 F8 也只有一个录音"
reset_logs
rm -f "$RUN/take"
vd toggle &
vd toggle &
wait
sleep 0.2
n_listen=$(grep -c '^notify 正在听' "$T/notify.log")
if [ -e "$RUN/record.pid" ]; then vd toggle; fi
wait_idle
[ "$n_listen" = 1 ] && pass "只开始了一次" || fail "开始了 $n_listen 次"

echo "== status 不报错"
vd status > /dev/null && pass "status" || fail "status 失败"

rm -rf "$T"
if [ "$fails" -gt 0 ]; then
  echo "voice-dictation-tests: $fails 项失败" >&2
  exit 1
fi
echo "voice-dictation-tests: 全部通过"
