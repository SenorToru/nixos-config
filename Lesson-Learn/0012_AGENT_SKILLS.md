# Agent Skills 使用指南

装的是 [mattpocock/skills](https://github.com/mattpocock/skills) 的 25 个
skill，全局安装，**Claude Code、GitHub Copilot、Zed、Gemini CLI 共用同一份**。

配置在 [`home/agent-skills.nix`](../home/agent-skills.nix)，
版本由 `flake.lock` 钉死，升级用 `skills-update`。

本文分两部分：**上半部分是手写的**，讲怎么用、有哪些坑；
**下半部分那张表是 `skills doc` 生成的**，跟着实际装的版本走，别手改。

---

## 一、Skill 是什么，什么时候会花钱

一个 skill 就是一个目录，里面一个 `SKILL.md`：YAML frontmatter（`name` +
`description`）加正文，可以再带几个附属文件。

**成本分两层，这是理解它的关键：**

| 层 | 内容 | 什么时候花 |
|---|---|---|
| 常驻 | `name` + `description` | **每个会话都花**，不管你用不用 |
| 调用 | `SKILL.md` 正文 | 只在这个 skill 被触发时 |
| 附属 | 正文里指向的 `.md` / `.sh` / `.yaml` | 正文让它读的时候才花 |

所以「多装几个 skill」的代价不是正文那几千 token，而是**常驻的那一行描述**。
25 个加起来常驻约 1k token —— 基本可以忽略，这也是「干脆全装」成立的理由。

想看实时数字：

```bash
skills list
```

## 二、主动调用 vs 被动调用

frontmatter 里带 `disable-model-invocation: true` 的，**只能你手打
`/名字`**；不带的，模型也能自己判断该不该用。

下面那张生成表的「调用方式」一列就是这个意思：

- **打 `/xxx`** —— 模型够不着，你不打就永远不会加载，等于零成本待命。
- **模型自动 / 也可手打** —— 模型读到 description 觉得对路就会自己拉进来。

⚠️ **`disable-model-invocation` 是 Claude Code 专属字段。**
Zed / Copilot / Gemini 多半不认它，在那些工具里，标着「打 `/xxx`」的
skill 同样可能被模型自己捡起来。跨工具用的时候心里有数。

## 三、装在哪，为什么是这个装法

```
第一层（声明式，home-manager 管，flake.lock 钉死版本）
  ~/.local/share/agent-skills -> /nix/store/…-agent-skills/
      ├── tdd/SKILL.md
      ├── matt-code-review/SKILL.md
      └── …

第二层（可变状态，skills 命令管，状态存 ~/.local/state/agent-skills/disabled）
  ~/.claude/skills/tdd    -> ~/.local/share/agent-skills/tdd
  ~/.agents/skills/tdd    -> 同上
  ~/.copilot/skills/tdd   -> 同上
```

各家认的全局目录：

| 工具 | 目录 |
|---|---|
| Claude Code | `~/.claude/skills/`（**只认这一个**，不读 `.agents`） |
| VS Code Copilot | `~/.copilot/skills/`、`~/.claude/skills/`、`~/.agents/skills/` |
| Copilot CLI | `~/.copilot/skills/` |
| Zed（v1.4.2+） | `~/.agents/skills/` |
| Gemini CLI | `~/.gemini/skills/` 或 `~/.agents/skills/`（后者优先） |

`~/.agents/skills/` 是新工具的汇合点，将来再出编辑器大概率也读它。

**为什么非要分两层：** 如果让 home-manager 直接管第二层那些链接，
`skills off tdd` 之后下一次 `nrb` 会把它**悄悄装回来** —— 这种 bug 最难查。
把「装了哪些」和「开着哪些」拆开，禁用状态就能活过 rebuild，
而新机器第一次 build 完是全开的，可复现性一点没丢。

代价是第二层不在 home-manager 的账本上，清理由 `skills sync` 负责。
它的剪枝判据很保守：**只动「原始链接目标落在 pool 里」的符号链接**，
不碰你手写的 skill，也不碰 `~/.claude/skills/synced/`（那是 Claude
云端同步的真目录，不是符号链接）。

## 四、和工具内建 skill 撞名

**`code-review` 装进来时会被改名成 `matt-code-review`。**

原因：Claude Code 自带一个内建的 `code-review`（就是 `/code-review`，
云端多 agent 审查）。同名的时候**内建赢** —— 文件确实装上了，
`ls ~/.claude/skills/` 看得见，但在 Claude Code 里根本够不着，
skill 目录里也不会列出来。

更坑的是其它工具没有这个内建，所以不改名的话，同一个名字在
Claude Code 里是内建那个、在 Copilot / Zed / Gemini 里是 Matt 那个 ——
同名不同物比单纯用不了难查得多。

改名在 `home/agent-skills.nix` 的 `skillSources.<源>.rename` 里配：

```nix
rename = {
  code-review = "matt-code-review";
};
```

它会**同时**改目录名和 `SKILL.md` frontmatter 里的 `name:` —— 只改目录名不够，
各家工具认 skill 的依据不完全一样，两边不一致会出现「目录叫 A、工具里显示成 B」。
`.manifest` 里记着原名，查得到是从哪个 skill 改过来的。

⚠️ **构建期的撞名检查只管源与源之间，查不到「和工具内建撞」** ——
那是运行时才知道的事，Nix 层面没法预知。以后装别的 skill 集合时，
装完记得在每个工具里数一遍：能看见的数量和 `skills list` 对不上，
差的那个多半就是撞了内建。

## 五、命令

```bash
skills list             # 全部 skill：调用方式、token 估算、开关状态
skills status           # pool 指向哪个 store 路径、三个目录的链接健不健康
skills off tdd          # 临时关掉一个，四个工具同时生效，活得过 nixos-rebuild
skills off --all        # 全关（想做个干净的对照实验时）
skills on --all         # 全开
skills sync             # 按开关状态重建链接（rebuild 时自动跑，平时用不到）
skills doc              # 重新生成本文下半部分的表
```

升级：

```bash
skills-update
```

它做的事，按顺序：`nix flake update`（**不带 sudo**，见
[`0011`](0011_ROOT_OWNED_FILES_IN_REPO.md)）→ 打印新旧 rev →
用户态构建系统层和 home 层 → 告诉你自己去 `nrb`。
**它不替你 switch，也不替你 commit。**

`nrb` 的时候会自动 `skills sync` + 刷新本文的生成表，
所以升级完 `git add` 的时候记得把 `flake.lock` 和本文一起带上。

## 六、加一个新的 skill 源

两处都要改，缺一不可：

1. `flake.nix` 加一个 `flake = false` 的 input；
2. `home/agent-skills.nix` 的 `skillSources` 表加一条，写明要装哪些类别。

`skills-update` 会自动把表里所有源一起更新，不用再改它。

名字撞车的话构建会直接失败并报出是哪两个源撞了 —— 这是故意的，
因为四家工具都只按目录名认 skill，悄悄覆盖比构建失败难查得多。
和工具**内建** skill 撞名则查不出来，要靠装完之后数数，见第四节。

装完记得 `skills list` 数一遍，再在每个工具里数一遍，两个数对不上就是撞了内建。

## 七、后续注意事项

- **没装 `in-progress/` 和 `misc/` 两个类别。** 前者是作者自己标的半成品；
  后者的 `git-guardrails-claude-code` 会和本仓库 `CLAUDE.md`
  「不要自动提交」的约定抢同一件事的管辖权。要装就去改 `skillSources`。
- **表里 8 个 issue-tracker 流水线的 skill**（`triage`、`to-spec`、
  `to-tickets`、`implement`、`wayfinder`、`ask-matt`、`grill-with-docs`、
  `setup-matt-pocock-skills`）需要先在**每个仓库**里跑一次
  `/setup-matt-pocock-skills`，配好 issue tracker 和文档位置才好用。
  不跑也不会坏，只是那几个 skill 会问你一堆它本该知道的事。
- **token 数是字符数 ÷ 4 的英文经验估算**，误差约 ±15%。要精确值得调
  Anthropic 的 `count_tokens` API，换算逻辑集中在
  `home/agent-skills.nix` 里的 `tok()` 一个函数里。
- **改 `skills` 脚本之前先看第八节。** 剪枝逻辑有回归测试挡着，
  测试不过整个 home 层就构建不出来。
- **构建通过 ≠ 可用。** 符号链接这种东西必须实机验证：
  `nrb` 之后在 Neovide 和 VSCode 里各开一次 `/tdd` 看看认不认。
  验证命令见下面「实机验证」。

## 八、回归测试

`home/skills-tests.sh` 是 `skills` 命令的回归测试，**在构建期跑** ——
测试不过就 build 不出来，`nhm` / `nrb` 直接停在那一步，不用等运行时发现。

**接缝（seam）是 CLI 边界。** 给定一个临时 `HOME`、一个 pool 夹具、
一份 disabled 状态文件，跑 `skills sync` / `on` / `off`，
断言三个目标目录里符号链接的**最终状态**。不测 `fm`、`catalog_chars`
那些内部函数 —— 它们是实现细节，重构内部结构不该让测试变红。

目前只有一条用例：**pool 之外的符号链接不会被 `sync` 删掉**。
先测这条是因为它后果最重：`~/.claude/skills/` 是用户自己也会往里放东西的
目录，误删不可逆；而剪枝逻辑又必须存在（换了 store 路径之后得清断链）。
两个要求拉扯的地方最容易写错。

用例里第二条断言（「pool 里的 skill 确实被装上了」）是**守住测试本身**的：
要是 `sync` 其实什么都没干，第一条会假阳性地通过。

手动跑：

```bash
SKILLS_BIN=$(command -v skills) bash home/skills-tests.sh
```

**改完剪枝逻辑，先确认测试能变红再提交。** 验证办法是把
`cmd_sync` 里的 `case "$(readlink "$l")" in "$POOL"/*) rm -f "$l" ;; esac`
临时改成无条件 `rm -f "$l"`，构建应当失败并打印
`FAIL  pool 之外的符号链接被 sync 删掉了`。一条永远不会红的测试等于没有。

下一批该补的用例（还没写）：

- `~/.claude/skills/synced/` 这种**真目录**不能被剪掉（现在只测了符号链接）
- `off <名字>` 之后三个目录里都不再有它，`on` 之后都回来
- 指向 pool 里已不存在项的**断链**要被剪掉
- `off --all` 之后 pool 本身不受影响

## 九、实机验证

```bash
skills status                          # 三个目录各能看见多少个
ls -l ~/.claude/skills/ | head         # 链接指向 ~/.local/share/agent-skills/
readlink -f ~/.local/share/agent-skills   # 落在 /nix/store 里
find . ! -user toru -printf '%u  %p\n'    # 应该没有任何输出（坑 5）
```

然后在 Claude Code 里打 `/tdd`，在 VS Code Copilot 里问一个该触发
`diagnosing-bugs` 的问题，各验一次。

**还要数一遍数量。** `skills list` 说 25 个，就去每个工具的 skill 列表里数，
少了就是和该工具的内建撞了名（见第四节）。`code-review` 就是这么发现的 ——
它在 Claude Code 里既不报错也不出现，只是静悄悄地少一个。

---

## 十、全部 skill 一览

<!-- BEGIN GENERATED: skills doc -->

> 这张表由 `skills doc` 生成，每次 `nixos-rebuild switch` 自动刷新。
> **别手改**，改动会被下一次生成覆盖；要改就去改生成逻辑
> （`home/agent-skills.nix` 里的 `cmd_doc`）。
>
> 对应的 skill 池：`/nix/store/f0aalgngcycbq7fgbfikfgqlrw5s65w7-agent-skills`

| Skill | 调用方式 | 常驻 tok | 调用 tok | 附属 tok | 用途（作者原文 description，这也是模型看到的触发条件） |
|---|---|---:|---:|---:|---|
| `ask-matt` | 打 `/ask-matt` | 23 | 2813 | 1097 | Ask which skill or flow fits your situation. A router over the skills in this repo. |
| `codebase-design` | 模型自动 / 也可手打 | 70 | 1440 | 1330 | Shared vocabulary for designing deep modules. Use when the user wants to design or improve a module's interface, find deepening opportunities, decide where a seam goes, make code more testable or AI-navigable, or when another skill needs the deep-module vocabulary. |
| `diagnosing-bugs` | 模型自动 / 也可手打 | 43 | 2082 | 355 | Diagnosis loop for hard bugs and performance regressions. Use when the user says "diagnose"/"debug this", or reports something broken/throwing/failing/slow. |
| `domain-modeling` | 模型自动 / 也可手打 | 42 | 754 | 1281 | Build and sharpen a project's domain model. Use when discussing codebase terminology, writing or editing a CONTEXT.md, or recording or editing an ADR. |
| `grill-me` | 打 `/grill-me` | 15 | 10 | 35 | A relentless interview to sharpen a plan or design. |
| `grill-with-docs` | 打 `/grill-with-docs` | 31 | 17 | 37 | A relentless interview to sharpen a plan or design, which also creates docs (ADR's and glossary) as we go. |
| `grilling` | 模型自动 / 也可手打 | 40 | 447 | 29 | Grill the user relentlessly about a plan, decision, or idea. Use when the user wants to stress-test their thinking, or uses any 'grill' trigger phrases. |
| `handoff` | 打 `/handoff` | 24 | 171 | 36 | Compact the current conversation into a handoff document for another agent to pick up. |
| `implement` | 打 `/implement` | 18 | 76 | 35 | "Implement a piece of work based on a spec or set of tickets." |
| `improve-codebase-architecture` | 打 `/improve-codebase-architecture` | 39 | 1445 | 1702 | Scan a codebase for deepening opportunities, present them as a visual HTML report, then grill through whichever one you pick. |
| `matt-code-review` | 模型自动 / 也可手打 | 110 | 1525 | 25 | "Review the changes since a fixed point (commit, branch, tag, or merge-base) along two axes: Standards (does the code follow this repo's documented coding standards?) and Spec (does the code match what the originating issue/spec asked for?). Runs both reviews in parallel sub-agents and reports them side by side. Use when the user wants to review a branch, a PR, work-in-progress changes, or asks to \"review since X\"." |
| `prototype` | 模型自动 / 也可手打 | 47 | 677 | 3263 | Build a throwaway prototype to answer a design question. Use when the user wants to sanity-check whether a state model or logic feels right, or explore what a UI should look like. |
| `research` | 模型自动 / 也可手打 | 62 | 130 | 24 | Investigate a question against high-trust primary sources and capture the findings as a Markdown file in the repo. Use when the user wants a topic researched, docs or API facts gathered, or reading legwork delegated to a background agent. |
| `resolving-merge-conflicts` | 模型自动 / 也可手打 | 25 | 198 | 29 | "Use when you need to resolve an in-progress git merge/rebase conflict." |
| `setup-matt-pocock-skills` | 打 `/setup-matt-pocock-skills` | 52 | 1644 | 3145 | "Configure this repo for the engineering skills: set up its issue tracker, triage label vocabulary, and domain doc layout. Run once before first use of the other engineering skills." |
| `tdd` | 模型自动 / 也可手打 | 38 | 840 | 946 | Test-driven development. Use when the user wants to build features or fix bugs test-first, mentions "red-green-refactor", or wants integration tests. |
| `teach` | 打 `/teach` | 17 | 2332 | 2118 | Teach the user a new skill or concept, within this workspace. |
| `to-questionnaire` | 打 `/to-questionnaire` | 26 | 685 | 42 | Turn a decision you can't fully answer into a questionnaire for someone else to fill in. |
| `to-spec` | 打 `/to-spec` | 40 | 707 | 34 | "Turn the current conversation into a spec and publish it to the project issue tracker: no interview, just synthesis of what you've already discussed." |
| `to-tickets` | 打 `/to-tickets` | 65 | 1337 | 37 | Break a plan, spec, or the current conversation into a set of tracer-bullet tickets, each declaring its blocking edges, published to the configured tracker (edges as text in one file per ticket locally, or native blocking links on a real tracker). |
| `triage` | 打 `/triage` | 36 | 1589 | 3186 | Move issues and external PRs through a state machine of triage roles, categorise, verify, grill if needed, and write agent-ready briefs. |
| `wait-what` | 打 `/wait-what` | 16 | 69 | 40 | "Stop. That last message did not land: re-pitch it." |
| `wayfinder` | 打 `/wayfinder` | 52 | 2911 | 36 | Plan a huge chunk of work (more than one agent session can hold) as a shared map of decision tickets on your issue tracker, and resolve them one at a time until the way to the destination is clear. |
| `wizard` | 模型自动 / 也可手打 | 80 | 942 | 2166 | Generate an interactive bash wizard that walks a human through steps only they can perform. Use when provisioning infrastructure, setting up credentials or CI secrets, walking an unfamiliar third-party dashboard, or running a one-off migration or cutover. Don't invoke this for steps the agent can perform itself. |
| `writing-for-agents` | 模型自动 / 也可手打 | 31 | 2683 | 683 | Writing documents for agents. Use when creating or editing skills, or modifying AGENTS.md or CLAUDE.md. |

合计 **25** 个 skill：常驻 ≈ **1032 tokens**（每个会话都付），正文全加起来 ≈ 27514 tokens，附属文件另计 ≈ 21702 tokens。

token 数是字符数 ÷ 4 的英文经验估算，误差约 ±15%。

<!-- END GENERATED -->

---

## 相关文档

- [`0010`](0010_CLAUDE_CODE_VERSION_PINNING.md) —— claude-code 本身的版本钉法
- [`0011`](0011_ROOT_OWNED_FILES_IN_REPO.md) —— 为什么 `nix flake update` 永远不加 sudo
- [`000D`](000D_CLAUDE_CODE_IN_NEOVIM.md) —— Neovide 里怎么接入 Claude Code
- [`README.md`](../README.md) —— 「Agent Skills」一节是操作手册版
