# 0019 语音输入：F8 / F9，Qwen3-ASR + Qwen3.5-9B，全部在本机跑

> **日期：** 2026-11-21 ・ **主机：** asus ・ **实现者：** Claude（Opus 5.5）
> **原始规格：** [VOICE_DICTATION.md](../VOICE_DICTATION.md)（Grok 写，记录了 Toru 的选择）
> **代码：** `modules/voice-dictation.nix`、`home/voice-dictation.nix`、`home/voice-dictation.py`、`home/voice-dictation-tests.sh`

**写给以后接手的人（包括 Grok）。** 这份记录讲清楚四件事：Toru 要什么、他自己定了什么，
实现前在这台机器上查到和测到了什么，最后怎么做的，
以及哪几处**没有照原规格做**、各自的实测依据。想改这块，先读第 5 节和第 7 节。

一句话结论：**原规格的「交互」部分全部照做，「模型和管线」部分按实测换掉了三样。**
Whisper large-v3 在中日英混说时会悄悄翻译、丢句，换成 Qwen3-ASR-1.7B，并在停顿处切段识别。
Qwen3-14B 慢五到十倍，还会把示范句的内容编进结果，换成 Qwen3.5-9B。
「按窗口发不同粘贴键」在 GNOME Wayland 上做不到，统一改发 Shift+Insert。

---

## 1. 需求：Toru 要什么，他定了什么

### 他为什么要这个

在 Grok Build 和 Claude Code 里，最大的瓶颈是打字速度。他说话跟着思路走，时快时慢，
说到一半会停下来想。同一段话里中文、日语、英语随意换。用过的语音输入里，
只有 iPhone 的跟得上他的节奏。他要的是人机配合：不用背稿，说错了直接说
「不对，我的意思是……」，让模型按最新的意思覆盖前面的。

### 他自己做的选择（来自 VOICE_DICTATION.md「讨论里他选过的」）

下表是 Toru 的原话选择，以及这次实现**是否照做**。

| Toru 的选择 | 实现 |
|------|------|
| 字打进当前焦点窗口（终端、浏览器、编辑器），不要专用输入框 | ✅ 照做 |
| 按一下开始，再按一下结束；停顿、静音不结束；不要按住说 | ✅ 照做 |
| 同一句里中日英随意换，不手选语言 | ✅ 照做，而且这是换掉 Whisper 的原因（第 3.1 节） |
| 只用 asus | ✅ 照做；thinkpad 只 import 模块让选项存在，开关保持 false |
| 先本机，第一版不把语音上传 | ✅ 照做，全部本机 |
| 每个窗口都先经本机模型整理再粘贴 | ✅ 照做 |
| 说话时只显示「正在听」，第二次按键后整段才出现，不要边说边出字 | ✅ 照做 |
| 整理只改口误：去嗯啊和重复、按改口覆盖、补标点；只有说「整理成……」才重排；短指令保持短 | ✅ 照做；提示词在这几条之外**加了约束和示范**（第 3.3 节） |
| 整理改坏了要能立刻拿回原文，用另一个键 | ✅ 照做（F9），并扩展了 F9 在听、整理时的用法（第 5 节） |
| 第二次按键后慢一点没关系，可以换更大的模型；没选「别超过十秒」 | ✅ 尊重，但实测更大的模型**更差**，最后用了更小更快的（第 3.4 节） |
| 识别用 Whisper large-v3，整理用约 14B 的 Qwen | ❌ **换了**，见第 3.1、3.4 节 |
| 第一版不接 Gemini | ✅ 照做 |
| F8 开始 / 结束，F9 贴原文；不占 Ctrl+Alt+T / Ctrl+Alt+Enter | ✅ 照做 |
| 失败时通知一行原因，原文留给 F9；不要结束别的 GPU 进程 | ✅ 照做 |
| 不喜欢能彻底回到现在：`custom.voiceDictation.enable = false` | ✅ 照做，第 4.6 节 |

2026-11-21 他让 Claude 实现，并说：**不必完全照规格做，可以用自己的调查和判断，
目标是在这台 asus 上用起来最舒服**。下面那些改动都是在这个授权下做的，每一处都有实测。

---

## 2. 调查：这台机器上的事实

| 项 | 值 |
|----|----|
| CPU / 内存 | Ryzen AI 7 H 350（16 线程，Zen 5）/ 30 GiB，zram 是唯一的 swap |
| 独显 | RTX 5060 Laptop，**8151 MiB**，Blackwell（compute capability 12.0），PRIME offload，空闲时 runtime PM 让它睡 |
| 驱动 / CUDA | 595.71.05 / nixpkgs 的 `cudaPackages` 是 12.9（支持 sm_120） |
| 桌面 | GNOME 50.5，Wayland。Mutter **没有** `ext/wlr-data-control`，有 `zwp_primary_selection` |
| 音频 | PipeWire 1.6.6，默认源是内置 ALC256 模拟输入 |
| 本 lock 的包 | `llama-cpp` **b9190**、`whisper-cpp` 1.8.4、`ydotool` 1.0.4、`wl-clipboard` 2.3.0、Ghostty 1.3.1 |
| Ghostty 默认键 | `ctrl+shift+v` = 剪贴板粘贴，**`shift+insert` = primary 选区粘贴** |
| `/dev/uinput` | 已有 toru 的 ACL（Steam 的 udev 规则给的），但不依赖它 |
| 同卡的别的程序 | promo-video-kit 的 Qwen3-TTS（PyTorch，批处理，跑完就退出） |

**关键发现：** 本 lock 的 llama.cpp b9190 已经原生支持 **Qwen3-ASR**（`tools/mtmd`，
投影器类型 `qwen3a`）和 **Qwen3.5**（`qwen35` 架构），还有 `--fit`（显存不够时把放不下的层留在内存）、
unix socket 监听。原规格写成时（2026-11-15）没有考虑这条路。

Qwen3-ASR 官方报告里和 Whisper large-v3 的对比（错误率，越低越好）：

| 测试集 | Whisper large-v3 | Qwen3-ASR-1.7B |
|--------|-----------------:|---------------:|
| WenetSpeech net / meeting（中文实录） | 9.86 / 19.11 | 4.97 / 5.88 |
| AISHELL-2 | 5.06 | 2.71 |
| Fleurs-zh | 4.09 | 2.41 |
| Fleurs 多语种平均 | 5.27 | 4.90 |
| 语种识别准确率（Fleurs） | 94.6 % | 98.7 % |

另外，HF 上下载最多的 Qwen3-ASR GGUF 是 `handy-computer/Qwen3-ASR-1.7B-gguf`（约 263 万次）。
这个组织名对应开源的本地听写软件 Handy，可见这个模型已经被拿来做同样的事。

---

## 3. 实测

测试音频用 promo-video-kit 的 Qwen3-TTS 合成（只读用，没改它的任何东西），
再拼上粉红噪声模拟停顿。所有命令都在 asus 上、用本 lock 的二进制跑。

| 录音 | 内容 |
|------|------|
| mixed（36 秒） | 中文（含 home-manager、Ghostty、rebuild）→ 停 3 秒 → 日语改口「違う、フォントじゃなくて…」→ 停 2 秒 → 英语一句 → 停 4 秒 → 中文改口「不对，我的意思是…」 |
| todo（24 秒） | 中文碎碎念 + 「请帮我把上面这些整理成待办清单」→ 停 3 秒 → 日语一句 |
| shortpause / longpause | 中文短句 → 日语 → 英语，中间停 1 秒 / 20 秒 |
| empty | 3 秒噪声，没有人声 |

### 3.1 识别：Whisper large-v3 会悄悄翻译和丢句

同一段 mixed，Whisper large-v3（whisper.cpp，`-l auto`）：

```
うん。 我想讓你幫我看一下。那個Home Manager的配置、就是、就是Ghosty那一塊。為什麼Rebuild之後字體沒有變?
あ、ちょっと待って。違うフォントじゃなくて、テーマの色が反映されてないんです。そう。
私の意思は、先に文件を変えないで、原因を見てみるだけでいい。
auto-detected language: ja (p = 0.454144)
```

- 整段判成日语，置信度只有 0.45
- 中文出成繁体
- **英语那句「So basically, check the stylix target first…」整句没了**，换成一个「そう。」
- **最后一句中文被翻译成了日语**

todo 那段被判成中文，**日语那句被翻译成中文，而且译错了**（「请你再次确认这些设定的文件再次公布」）。

同样两段，Qwen3-ASR-1.7B（llama-mtmd-cli，冷启动含加载模型 2.8 秒 / 1.7 秒）：

```
language Chinese<asr_text>嗯，我想让你帮我看一下那个 Home Manager 的配置，就是就是 Ghosty 那一块，
为什么 rebuild 之后字体没有变？啊，ちょっと待って、違うフォントじゃなくてテーマの色が反映されてないんです。
So basically, check the Stylix target first, and then tell me what you find。不对，我的意思是先别改文件，只看一下原因就行。
```

三种语言各自用各自的文字，自带标点。错的只有 Ghosty、「代办」（待办）。
在 system 消息里放专有名词表（Qwen3-ASR 叫「上下文」）之后，Ghostty 对了。
「待办」只有在上下文里写进这个中文词时才对，而第 3.2 节说明了上下文里不能放中文词，
所以现在仍会听成「代办」。它通常出现在「整理成待办清单」这句要求里，整理时这句会被删掉，影响不大。

**结论：** 原规格担心的是「混说会整段偏向一种语言」。实测 Whisper 的问题比这严重：
它会**不报任何错地翻译或丢掉整句**，用户看到的是一段通顺但不是自己说的话。换掉。

### 3.2 识别：Qwen3-ASR 整段送也会塌，要按停顿切段

继续测 shortpause / longpause 时，Qwen3-ASR 也出了同一类问题：

| 录音 | 设置 | 结果 |
|------|------|------|
| longpause | 上下文「NixOS, Ghostty, Claude Code, Grok」 | 判成 English，**中文被译成英语，日语整句丢掉** |
| longpause | 不给上下文 | 对 |
| longpause | 上下文含中文词「待办」 | **日语被译成中文** |
| shortpause | 不给上下文 | **只剩英语那句，中文和日语都没了** |
| mixed（停 20 秒） | 不给上下文 | 对 |

**原因：** Qwen3-ASR 的输出先是一个整段的语言判断（`language English`），再是文字。
后面的识别都跟着这个判断走。一段里各语言分量差不多时（尤其结尾是英语），
判断会被拉偏，其它语言就被翻译或略过。这和 Whisper 是同一类问题，只是少见得多。
停顿长短不是原因；上下文会推一把，所以上下文里**只放拉丁字母的名字**。

**修法：** 用 Silero VAD（whisper.cpp 自带的 `whisper-vad-speech-segments`，CPU，每段录音 20〜60 毫秒）
找出人声段，在 **≥ 0.8 秒的停顿**处切开，**每段单独送去识别**，各自判语言。
Toru 换语言多发生在句与句之间的停顿处；句子里夹英文词的情况，同一段里模型本来就处理得好。

切段之后（含启动 llama-server 加载模型，冷启动）：

| 录音 | 结果 | 耗时 |
|------|------|-----:|
| shortpause | 中、日、英三句全对 | 1.87 s |
| longpause | 三句全对 | 1.65 s |
| mixed | 全对 | 1.98 s |
| todo | 全对 | 1.72 s |
| empty | 空（VAD 0 段），什么也不贴 | — |

### 3.3 整理：提示词改了六版

整理模型用 Qwen3.5-9B Q4_K_M。测试句是上面两段的识别结果，加上短指令
「帮我跑一下 Nix build，看看有没有报错。」、提问「NixOS 的 flake 到底是什么意思？」、
日语提问、英语改口。

| 版本 | 改了什么 | 出的错 |
|------|----------|--------|
| v0 | 原规格的提示词，一字不改 | mixed 里的**日语和英语被译成中文**；todo 的日语条目被译成中文 |
| v1 | 加「每句保留原来的语言」「不要回答」「保留措辞」 | 矫枉过正：**不敢删了**（えーと和连说两遍的词都留着）；**「整理成待办清单」也不做了**，因为写了「不要执行」 |
| v2 | 明确「整理成……是唯一要照做的请求」，列出口头禅，加 6 条示范 | 好了很多；跨语言改口时日语仍被译成中文 |
| v3 | 整份改成英文写 | 句中日语保住了，但「Actually scratch that, put it in MIGRATION.md」被**删掉改口、留下被推翻的那句**，意思反了 |
| v4 | 回到中文，「不要翻译」改成「每个词都保留说它时的语言，同一句里混着说也一样」，修正一条本身就在教翻译的示范，再加两条示范 | 见下 |
| **v5（采用）** | v4 再加一条示范：多句、三种语言、中间用日语改口的长段（nginx 404 → 502） | 见下 |

**v4 在 8 句没调过参的新句子上全对**（改口、日语清单、句中混日语、英语提问），
旧测试句里 scratch that 和句中日语也对了。但 mixed 这种长段一直没做好：
改口后的日语被译成中文，英语那句被删掉（模型把最后的「不对，我的意思是」当成推翻了英语那句）。

**v5 是装好之后用正式构建出的命令重测时补的。** 前面调提示词用的是整段识别的旧文本；
换成切段识别的真实输出（标点、语气词略有不同）之后，v4 在 mixed 上更差了：

```
v4：home-manager 的 Ghostty 配置，rebuild 之后字体没有变。不对，我的意思是主题的颜色没有反映出来。先别改文件，只看一下原因就行。
v5：帮我看看 home-manager 里 Ghostty 那一块的配置，为什么 rebuild 之后主题颜色没有反映出来。先别改文件，只看一下原因就行。
```

v4 留下了被推翻的「字体没有变」和改口用的「不对，我的意思是」。v5 意思对了，日语仍被译成了中文。
对比过三种改法：只加示范（v5a）、只加一条「改口后的内容用什么语言说就保留什么语言」的规则（v5b）、两样都加（v5c）。
v5b 没修好；v5c 也修好了，但有一条短句退步（「那个，你先别 push……」的「那个」没删）。
采用 v5a，同一组 21 句连跑三遍结果完全一样，旧 mixed 甚至保住了日语和英语。
v5a 的小毛病和 v4 一样：日语清单里把原话的「テストを足して」写成了「テストを追加する」，意思不变。

**注意：llama.cpp 在温度 0 下也不是逐字可复现的。** 同一份 v4 前后两次跑，
有三句的措辞不一样（意思一样）。比较提示词时每个版本至少跑两遍，只看稳定出现的差异。

**还剩的毛病：**

| 情况 | 例子 | 结果 |
|------|------|------|
| 中文陈述之后用日语「いや、違う」推翻 | 我觉得是时区的问题。いや、違う、タイムゾーンじゃなくて、ロケールの問題かもしれない | 两句都留着，没有删被推翻的那句 |
| 改口后的内容换了语言 | ……为什么构建要二十分钟？あ、違う、二十分じゃなくて四十分かかってるんです | 意思改对了（四十分），但写成了中文句子 |
| 用中文改口推翻日语 | このスクリプト、Python で書き直してほしい。不对，我的意思是用 Rust 重写 | 意思改对了（Rust），但写成了日语 |
| 重排成清单 | 日语条目 | 偶尔译成中文，或者半中半日 |

这几种意思都没错，或者读的人一看就懂。真要原话就按 F9。

判断标准是**意思错不错，而不是像不像原文**：被翻译过去，Claude / Grok 一样读得懂；
改口处理反了，指令就错了。v3 比 v2 更「保留原文」，但出了意思反转，所以不选。

**思考模式不能开：** 打开 `enable_thinking` 后两段都在推理里打转，写满 4096 个 token
也没有输出，每段 92 秒。整理固定 `--reasoning off`。

示范句和测试句故意不重复，免得只是把测试句背下来。

### 3.4 整理：更大的模型更差

同一份 v2 提示词，三个模型（llama-server 已加载好之后的单句耗时）：

| 模型 | 显存 | 每句耗时 | 问题 |
|------|-----:|-------:|------|
| **Qwen3.5-9B Q4_K_M（采用）** | 5.8 GB，整份在卡上 | 0.4〜2 s | 跨语言改口偶尔翻译 |
| Qwen3.5-9B Q6_K | 6.5 GB | 1.3〜3.4 s | 改写得更狠：mixed 整段改写成中文，日语、英语都被译掉（「只检查 Stylix 配置并告诉我原因」） |
| Qwen3-14B Q4_K_M（原规格） | 文件 9.0 GB，卡上 6.5 GB，其余层在内存 | 3〜14 s | **把示范句的内容编进了结果**：待办清单里多出「修自行车」「给妈妈打电话」 |

14B 是原规格的选择，Toru 也说过慢点没关系。但它不只是慢，还会编造，所以不用。
Qwen3.5-9B（2026-02）是比 Qwen3-14B（2025-04）新一代的模型，整份放得进 8 GB 显存。

### 3.5 显存：两个模型不能同时在卡上

| 进程 | 峰值显存 |
|------|-------:|
| Qwen3-ASR-1.7B Q8_0 + mmproj（ctx 8192） | 约 3.6 GB |
| Qwen3.5-9B Q4_K_M（ctx 8192） | 约 5.8 GB |

加起来超过 8151 MiB，所以**先识别、识别进程退出、再起整理**，和原规格的顺序一致。

### 3.6 工具行为

| 实测 | 影响 |
|------|------|
| `pw-record` 起流约 0.3 秒；SIGINT 后退出码是 1，但 WAV 头已写完整 | 「正在听」等文件开始写数据才弹，看到通知再开口不会吞字；退出码 1 不当错误 |
| `ydotool` 连不上 ydotoold 时退出码 2 | 刚 switch、组还没生效时就是这样。提示手动粘贴，文字留在剪贴板 |
| `wl-copy` 在 GNOME 上正常（51 毫秒），primary 也能写 | 两个选区都写 |
| `wl-copy` fork 出的常驻进程继承 stdout | 必须接 DEVNULL，接管道的话 `subprocess.run` 永远等不到 EOF |
| CUDA 版 llama.cpp 只编 sm_120 | 6 分钟（16 线程），闭包约 1 GB（cuBLAS） |
| **ggml-org 在 2026-11-21 重新上传了 Qwen3-ASR 的 GGUF**（提交 `3b2c2958`） | 同名 Q8_0 文件从 2165034944 字节变成 2165035232 字节（多 288 字节），sha256 从 `58e22d05…` 变成 `cd5f5ce9…`。测过的是 2026-04-13 的提交 `36a67868`，URL 钉在它上面 |
| HF 下载中途断过一次（curl `-f -s` 静默退出） | `voice-dictation-models` 用 `-C -` 续传 + `--retry-all-errors` |

---

## 4. 实现

### 4.1 文件

| 文件 | 内容 |
|------|------|
| `modules/voice-dictation.nix` | 选项 `custom.voiceDictation.{enable,cudaArchitectures,llamaPackage}`；按 CUDA 架构编 llama.cpp；`programs.ydotool.enable` |
| `hosts/asus/default.nix` | `enable = true`；`extraGroups` 按开关追加 `ydotool` 组（用户名只出现在这里） |
| `hosts/asus/tuning.nix` | `cudaArchitectures = [ "120" ]`（绑在显卡上） |
| `hosts/thinkpad/default.nix` | 只 import 模块，让选项存在 |
| `home/voice-dictation.nix` | 专有名词表、模型清单（URL 钉提交 + 大小 + sha256）、整理提示词与示范、生成给脚本的 JSON、构建期测试、F8 / F9 两条 dconf 快捷键、Neovide 的 `<S-Insert>` 映射 |
| `home/voice-dictation.py` | 主程序，只用 Python 标准库 |
| `home/voice-dictation-tests.sh` | 状态机回归测试，构建期执行 |
| `home/desktop-prefs.nix` | `custom-keybindings` 列表按开关追加两条路径；构建期断言「关掉时追加的是空列表」 |

### 4.2 流程

```
F8（空闲）  -> 查模型戳记 -> pw-record 录 16 kHz 单声道 wav -> 等数据开始写 -> 通知「正在听」
              -> 后台让内核把模型文件读进页缓存（fadvise，不占显存）
F8（正在听）-> SIGINT 停录音 -> 通知「正在识别」-> 起后台流程：
              1. Silero VAD 找人声段，在 >=0.8 s 停顿处切开（<1 s 的并进邻段，>60 s 的在最长停顿处再切）
              2. llama-server（Qwen3-ASR，unix socket）起来，逐段识别，接起来 -> raw.txt -> 停掉
              3. 通知「正在整理」-> llama-server（Qwen3.5-9B）起来，整理 -> clean.txt -> 停掉
              4. 剪贴板、primary 都写成整理稿 -> ydotool 按 Shift+Insert -> 200 ms 后放回原剪贴板 -> 撤通知
```

状态只看两个 pid 文件（`$XDG_RUNTIME_DIR/voice-dictation/record.pid`、`process.pid`），
都在 tmpfs 上，重新登录就清空，不会留下过期状态。F8、F9 和后台流程改状态前都拿同一把文件锁。

### 4.3 按键

| 键 | 空闲 | 正在听 | 正在识别 | 正在整理 |
|----|------|--------|----------|----------|
| F8 | 开始听（缺模型时提示下载命令） | 结束，识别 + 整理 + 贴整理稿 | 忽略 | 忽略 |
| F9 | 贴上一段的原文 | 结束，只识别，贴原文 | 识别完贴原文，不整理 | 停掉整理，马上贴原文 |

### 4.4 失败时

| 情况 | 通知 | 贴不贴 |
|------|------|--------|
| 模型不在 | 模型还没下载 / 先运行 voice-dictation-models | 不录音 |
| VAD 0 段 | 没听到说话 | 不贴，也不加载模型 |
| 识别失败 | 识别失败：原因 / 可以 voice-dictation retry | 不贴，录音留着 |
| 整理失败、显存不够、超时 | ……，原文已留下 / 按 F9 贴原文 | 不贴（Toru 的选择） |
| 整理稿比原话长 1.6 倍以上 | 整理结果不像原话，原文已留下 | 不贴。多半是模型把提问当成问题去答了 |
| ydotool 失败 | 没能自动粘贴，文字在剪贴板里 / 刚 switch 过就注销再登录 | 文字留在剪贴板，不恢复 |

### 4.5 模型文件

`voice-dictation-models` 下载到 `~/.cache/voice-dictation/models/`，每个文件核对大小和 sha256，
通过后写一个 `<文件>.sha256` 戳记。之后 F8 只看大小和戳记，不再每次算 8.5 GB 的哈希。
已经下载好的文件再跑一次只做核对（实测 4 秒，文件在页缓存里）。
`voice-dictation-models --verify` 不看戳记，强制重算。

### 4.6 撤回

`custom.voiceDictation.enable = false` 再 `nrb`：

- `custom-keybindings` 回到两条开终端的（desktop-prefs.nix 里有构建期断言）
- `voice-dictation` 命令和它引用的 llama.cpp、whisper-cpp 都不在闭包里
- `programs.ydotool` 关掉：ydotoold 服务、`ydotool` 组、`YDOTOOL_SOCKET` 变量都没了
- `extraGroups` 里的 `ydotool` 按同一个开关消失
- Neovide 的 `<S-Insert>` 映射消失（`init.lua` 用 `lib.mkAfter` 追加，同样挂在开关上）
- Ghostty、Dash to Panel、Astra Monitor、DNS、Agent Skills 没有被碰过

dconf 里 `voice-dictation-toggle/`、`voice-dictation-raw/` 两个子节的旧值会留在用户的 dconf 库里
（home-manager 不删已经不声明的键），但它们不在 `custom-keybindings` 列表里，GNOME 不会读。
想清干净：`dconf reset -f /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/voice-dictation-toggle/`，raw 同理。

### 4.7 端到端实测

用正式构建出的命令（`/tmp/hm/home-path/bin/voice-dictation`，CUDA 版 llama.cpp b9190），
模型在页缓存里，每次都从加载模型开始（和按 F8 时一样）：

| 录音 | 长度 | `transcribe`（VAD + 加载 + 识别） | `clean`（加载 + 整理） |
|------|-----:|------:|------:|
| mixed | 35.9 s | 2.26 s | 3.29 s |
| todo | 24.2 s | 1.71 s | 3.09 s |
| shortpause | 16.7 s | 1.61 s | 3.22 s |
| longpause | 54.7 s | 1.66 s | — |
| empty | 3.0 s | 1.07 s（0 段，没有加载模型） | — |
| 短指令 | — | — | 2.59 s |

从第二次 F8 到贴出，大约是两列相加再加粘贴的 0.2 秒：**4.5〜6 秒**。
F9 结束（不整理）约 2 秒。时间主要花在加载模型上，整理本身 0.5〜1.5 秒。

**没在实机上走过的一步：** 按 F8 / F9、ydotool 真的把字贴进窗口。
要等 `nrb` 和重新登录（`ydotool` 组）之后才能试。状态机、粘贴顺序、剪贴板恢复都在构建期测试里覆盖了（外部程序是假的）。

---

## 5. 和 VOICE_DICTATION.md 的差异

| 原规格 | 实际 | 依据 |
|--------|------|------|
| Whisper large-v3（whisper.cpp） | **Qwen3-ASR-1.7B**（llama.cpp mtmd） | 3.1 节：Whisper 混说时翻译、丢句；Qwen3-ASR 三种语言都对，中文错误率约一半 |
| 整段一次识别 | **按停顿切段，每段单独识别** | 3.2 节：整段送会被一个语言判断带偏 |
| 约 14B Qwen，装不下的层走内存 | **Qwen3.5-9B Q4_K_M，整份在卡上** | 3.4 节：14B 慢五到十倍，还会编造 |
| 提示词一字不改 | 保留 Toru 那几条，**加约束和 9 条示范** | 3.3 节：原版会把日语、英语译成中文；第 9 条是装好后用真实识别结果重测时补的 |
| 读焦点窗口的 wm class，Ghostty 发 Ctrl+Shift+V，别处 Ctrl+V | **一律 Shift+Insert，剪贴板和 primary 都写** | GNOME Wayland 上没有扩展就拿不到焦点窗口（`Shell.Eval` 关着）。Shift+Insert 在 Ghostty 读 primary、在别处读剪贴板 |
| 「正在整理」一条通知 | 「正在识别」→「正在整理」两段 | 原规格里这条标着是方案作者（Grok）的判断，不是 Toru 的选择。分两段能看出进度 |
| 「正在听」普通通知 | critical + transient：一直留在屏幕上直到被替换 | Toru 拿 iPhone 当参照是因为「看得到它还在听」。普通通知几秒就收起 |
| F9 只在空闲和整理时有用，听的时候不动作 | **F9 在任何时候都表示「这一段我要原文」**（见 4.3） | 准备好的短指令用 F9 结束，跳过整理，最快。仍然是同一套键，没有第二种模式 |
| Whisper 没写完时 F9 不动作 | 识别中按 F9：识别完直接贴原文 | 同上 |
| 用 Whisper 时要 whisper-cpp CUDA 版 | whisper-cpp 只用 CPU 版的 VAD 工具，**二进制缓存里就有** | 只要一份 CUDA 编译（llama.cpp），6 分钟 |
| 用户服务 | 不用 systemd 单元，pid 文件 + 文件锁 | 状态在 tmpfs，崩了不留过期状态；构建期测试不用假 systemd |
| — | 整理稿比原话长出一大截就不贴 | 防模型把提问当成问题去答 |
| — | 录音开始时 fadvise 预读模型文件 | 开机后第一次用不用等磁盘，不占显存 |
| — | Neovide 里 `<S-Insert>` 映射成粘贴 | Neovide 是图形程序，nvim 直接收到这个键，默认什么也不做 |
| 模型仓库、文件名写进模块 | 另外**钉了提交**，配大小和 sha256 | 3.6 节：上游当天就重新上传过 |

照原规格做的：F8 / F9 这两个键、不占开终端的快捷键、按一下开始再按一下结束、静音不结束、
听的时候不加载模型、识别进程退出后再起整理、失败时原文留给 F9、不结束别的 GPU 进程、
剪贴板贴完放回去（200 ms）、ydotool 只送键码、`programs.ydotool`、
模型在 `~/.cache/voice-dictation` 不进 store 不进 `stateFiles`、开关默认 false、
用户名只在 hosts、`writeText` 落提示词（这里是整份 JSON）、不在 nix 字符串里写 heredoc、
构建期状态机测试、文档同步。

---

## 6. 为什么这样解决

**一、宁可慢一点，也不能「通顺但不是我说的」。** 语音输入最伤人的错，
是给出一段看起来没问题、其实被翻译过或少了一句的话：用户不会逐字核对，
发出去才发现指令不对。Whisper 和整段送的 Qwen3-ASR 都会这样错。
切段多了几次请求（每段几十到几百毫秒），换来的是不会塌。

**二、更大的模型不一定更好，要测。** Toru 选 14B 的前提是「越大越准」。
在这个任务上（只删不改、保持语言），实测 9B 新一代模型比 14B 旧模型更守规矩，
还快五到十倍。用户说过「慢一点没关系」，不等于慢就是对的。

**三、显存让给别人。** 这块 8 GB 的卡还要跑 Qwen3-TTS。模型现加载、用完退出：
听的时候、空闲的时候都不占显存，独显也能睡下去省电。代价是每段多几秒加载时间。

**四、能在 GNOME 上真正工作的方案优先。** 按窗口发不同键的设计依赖一个这台桌面不提供的能力。
Shift+Insert + 两个选区不依赖任何扩展。

**五、撤回要完整。** 所有新东西都挂在一个开关上，关掉之后快捷键列表有构建期断言守着。

---

## 7. 后续注意事项

- **改提示词之前**，用 `voice-dictation clean "<口述>"` 对着第 3.3 节的句子试；
  加示范时别和测试句重复。规则里后加的每一条都对应一个实际出过的错。
- **经常听错的词**加进 `home/voice-dictation.nix` 的 `vocabulary`（只放拉丁字母的名字），`nrb` 即可。
- **一句话被切碎、或换语言没切开**：调 `vad.min_gap_s`（现在 0.8 秒）。
  调小切得更碎，单段太短时判语言会不稳；调大的话，语言之间停顿短时又会塌回第 3.2 节的问题。
- **Ghostty 里偶尔贴丢**：只调 `paste_delay_ms`（现在 200）。
- **换模型**：改提交、文件名、大小、sha256 四项，跑 `voice-dictation-models`。
  先用 `voice-dictation transcribe` / `clean` 对着第 3 节的录音和句子比一遍。
  新的 GGUF 可能要更新的 llama.cpp。
- **换显卡**：改 `hosts/<主机>/tuning.nix` 的 `cudaArchitectures`
  （`nvidia-smi --query-gpu=compute_cap --format=csv`，12.0 写成 `"120"`）。
- **thinkpad 想用**：打开 `enable`，不写 `cudaArchitectures` 就是 CPU 版，能用但整理慢很多。
- **已知限制**：一句话里中日混说、中间又没有停顿时，靠模型自己处理，偶尔会把短的那部分译掉；
  跨语言改口的几种情况见第 3.3 节末尾的表；「待办」会听成「代办」（第 3.1 节）。都可以 F9 拿原文。
- **调提示词用真实识别结果，不要用手打的文本。** v5 那条示范就是因为调参用的是整段识别的旧文本，
  换成切段识别的真实输出才暴露问题。`voice-dictation transcribe <wav>` 先拿到识别结果，再喂给 `clean`。
- **测试**：`home/voice-dictation-tests.sh` 在构建期跑。改状态机之前先确认它能变红。
  这次的做法是复制一份 `voice-dictation.py`，删掉「整理中忽略 F8」那两行，跑测试，必须失败（实测失败 4 项）。
- **没做的**：边说边出字（Toru 不要）、多段合并（Toru 不要）、Gemini（第一版不接）、
  常驻模型（显存要让给 TTS）、给 F8 加取消键（误按就再按一次，没说话时不会贴任何东西）。

---

## 8. 相关文档

- [VOICE_DICTATION.md](../VOICE_DICTATION.md) —— 原始规格和 Toru 当时的选择
- [README.md](../README.md)「语音输入」 —— 日常用法、第一次用、撤回
- [CLAUDE.md](../CLAUDE.md)「语音输入：F8 / F9」 —— 改这块之前必须知道的八件事
- [MIGRATION.md](../MIGRATION.md) 第 0 节、第 10 节 —— `~/.cache/voice-dictation` 不搬
- [0012_AGENT_SKILLS.md](0012_AGENT_SKILLS.md) —— 构建期测试挂进依赖链的同一个做法
- [0015_CLAUDE_CODE_NEOVIDE_WORKFLOW.md](0015_CLAUDE_CODE_NEOVIDE_WORKFLOW.md) —— Neovide 里剪贴板键位的由来
