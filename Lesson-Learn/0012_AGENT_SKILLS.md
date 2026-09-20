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
      ├── code-review/SKILL.md
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

## 四、命令

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

## 五、加一个新的 skill 源

两处都要改，缺一不可：

1. `flake.nix` 加一个 `flake = false` 的 input；
2. `home/agent-skills.nix` 的 `skillSources` 表加一条，写明要装哪些类别。

`skills-update` 会自动把表里所有源一起更新，不用再改它。

名字撞车的话构建会直接失败并报出是哪两个源撞了 —— 这是故意的，
因为四家工具都只按目录名认 skill，悄悄覆盖比构建失败难查得多。

## 六、后续注意事项

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
- **构建通过 ≠ 可用。** 符号链接这种东西必须实机验证：
  `nrb` 之后在 Neovide 和 VSCode 里各开一次 `/tdd` 看看认不认。
  验证命令见下面「实机验证」。

## 七、实机验证

```bash
skills status                          # 三个目录各能看见多少个
ls -l ~/.claude/skills/ | head         # 链接指向 ~/.local/share/agent-skills/
readlink -f ~/.local/share/agent-skills   # 落在 /nix/store 里
find . ! -user toru -printf '%u  %p\n'    # 应该没有任何输出（坑 5）
```

然后在 Claude Code 里打 `/tdd`，在 VS Code Copilot 里问一个该触发
`diagnosing-bugs` 的问题，各验一次。

---

## 八、全部 skill 一览

<!-- BEGIN GENERATED: skills doc -->

> 这张表由 `skills doc` 生成，每次 `nixos-rebuild switch` 自动刷新。
> **别手改**，改动会被下一次生成覆盖；要改就去改生成逻辑
> （`home/agent-skills.nix` 里的 `cmd_doc`）。
>
> 对应的 skill 池：`/nix/store/rwb9z1frc9f02hz6lhzgllv7q5b9yjzv-agent-skills`

| Skill | 调用方式 | 常驻 tok | 调用 tok | 附属 tok | 用途（作者原文 description，这也是模型看到的触发条件） |
|---|---|---:|---:|---:|---|
| `ask-matt` | 打 `/ask-matt` | 23 | 2813 | 1097 | Ask which skill or flow fits your situation. A router over the skills in this repo. |
| `code-review` | 模型自动 / 也可手打 | 108 | 1525 | 25 | "Review the changes since a fixed point (commit, branch, tag, or merge-base) along two axes: Standards (does the code follow this repo's documented coding standards?) and Spec (does the code match what the originating issue/spec asked for?). Runs both reviews in parallel sub-agents and reports them side by side. Use when the user wants to review a branch, a PR, work-in-progress changes, or asks to \"review since X\"." |
| `codebase-design` | 模型自动 / 也可手打 | 70 | 1440 | 1330 | Shared vocabulary for designing deep modules. Use when the user wants to design or improve a module's interface, find deepening opportunities, decide where a seam goes, make code more testable or AI-navigable, or when another skill needs the deep-module vocabulary. |
| `diagnosing-bugs` | 模型自动 / 也可手打 | 43 | 2082 | 355 | Diagnosis loop for hard bugs and performance regressions. Use when the user says "diagnose"/"debug this", or reports something broken/throwing/failing/slow. |
| `domain-modeling` | 模型自动 / 也可手打 | 42 | 754 | 1281 | Build and sharpen a project's domain model. Use when discussing codebase terminology, writing or editing a CONTEXT.md, or recording or editing an ADR. |
| `grill-me` | 打 `/grill-me` | 15 | 10 | 35 | A relentless interview to sharpen a plan or design. |
| `grill-with-docs` | 打 `/grill-with-docs` | 31 | 17 | 37 | A relentless interview to sharpen a plan or design, which also creates docs (ADR's and glossary) as we go. |
| `grilling` | 模型自动 / 也可手打 | 40 | 447 | 29 | Grill the user relentlessly about a plan, decision, or idea. Use when the user wants to stress-test their thinking, or uses any 'grill' trigger phrases. |
| `handoff` | 打 `/handoff` | 24 | 171 | 36 | Compact the current conversation into a handoff document for another agent to pick up. |
| `implement` | 打 `/implement` | 18 | 76 | 35 | "Implement a piece of work based on a spec or set of tickets." |
| `improve-codebase-architecture` | 打 `/improve-codebase-architecture` | 39 | 1445 | 1702 | Scan a codebase for deepening opportunities, present them as a visual HTML report, then grill through whichever one you pick. |
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

合计 **25** 个 skill：常驻 ≈ **1030 tokens**（每个会话都付），正文全加起来 ≈ 27514 tokens，附属文件另计 ≈ 21702 tokens。

token 数是字符数 ÷ 4 的英文经验估算，误差约 ±15%。

<!-- END GENERATED -->

---

## 相关文档

- [`0010`](0010_CLAUDE_CODE_VERSION_PINNING.md) —— claude-code 本身的版本钉法
- [`0011`](0011_ROOT_OWNED_FILES_IN_REPO.md) —— 为什么 `nix flake update` 永远不加 sudo
- [`000D`](000D_CLAUDE_CODE_IN_NEOVIM.md) —— Neovide 里怎么接入 Claude Code
- [`README.md`](../README.md) —— 「Agent Skills」一节是操作手册版
