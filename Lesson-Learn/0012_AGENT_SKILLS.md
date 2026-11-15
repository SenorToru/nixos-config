# Agent Skills 使用指南

全局安装，**Claude Code、GitHub Copilot、Zed、Gemini CLI、Grok 共用同一份**。
Grok 读 `~/.agents/skills/`，自带 skill 仍在 `~/.grok/bundled/skills/`。
三份源：

- [mattpocock/skills](https://github.com/mattpocock/skills) 的 22 个
  （源里另有 5 个在 `exclude` 里，不装）
- [ui-ux-pro-max-skill](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill)
  的 7 个：`ui-ux-pro-max`、`uupm-design`（上游目录名是 `design`）、
  `brand`、`design-system`、`slides`、`banner-design`、`ui-styling`
- [marketingskills](https://github.com/coreyhaines31/marketingskills)
  的 53 个，从 `skills/<名字>/` 整层装入。没有改名，没有排除。
  仓库根上的 `tools/` 不进池子；技能正文里指向它的相对链接在池子里对不上，
  那些集成是可选的，技能本身不靠它们才能加载。

下面那张表要等下一次 `nrb` 跑过 `skills doc` 才会列出这 53 个。
在那之前它还是上一版池子的 29 个。别手改生成段。

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
mattpocock 那 22 个常驻大约 800 token。ui-ux-pro-max 那 7 个、marketingskills
那 53 个也一样：正文再长，不开就不读，常驻只是各自 description 那一行。
53 个会让每个会话的常驻描述变长，精确数字等下次 `nrb` 之后看生成表。
源里另外 5 个没装，是因为用不上（`home/agent-skills.nix` 的 `exclude` 注释里写了理由），不是为了省钱。

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
| Grok | `~/.agents/skills/`（自带的在 `~/.grok/bundled/skills/`，不从这里装） |

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

**两处改名：`code-review` → `matt-code-review`，`design` → `uupm-design`。**

原因：Claude Code 自带一个内建的 `code-review`（就是 `/code-review`，
云端多 agent 审查）。同名的时候**内建赢** —— 文件确实装上了，
`ls ~/.claude/skills/` 看得见，但在 Claude Code 里根本够不着，
skill 目录里也不会列出来。

更坑的是其它工具没有这个内建，所以不改名的话，同一个名字在
Claude Code 里是内建那个、在 Copilot / Zed / Gemini 里是 Matt 那个 ——
同名不同物比单纯用不了难查得多。

`design` 是同一类问题的另一边：Grok 自带的 design 是写设计文档，
ui-ux-pro-max 仓库里的 design 是做界面。不改名的话 Grok 里够不着后者。
改名之后两个都在，调用后者用 `/uupm-design`。

改名在 `home/agent-skills.nix` 的 `skillSources.<源>.rename` 里配：

```nix
rename = {
  code-review = "matt-code-review";
};
# ui-ux-pro-max 那条是 design = "uupm-design";
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
                        # 长期不要的写进 home/agent-skills.nix 的 exclude，不靠这个
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
用户态构建**本机**系统层和 home 层 → 告诉你自己去 `nrb`。
构建哪台由 `custom.flakeHost` 决定，和 `nrb` 同一个来源，不写死某台机器。
**它不替你 switch，也不替你 commit。**

`nrb` 的时候会自动 `skills sync` + 刷新本文的生成表，
所以升级完 `git add` 的时候记得把 `flake.lock` 和本文一起带上。

## 六、加一个新的 skill 源

两处都要改，缺一不可：

1. `flake.nix` 加一个 `flake = false` 的 input；
2. `home/agent-skills.nix` 的 `skillSources` 表加一条。
   按类别放的写 `categories`。
   放在 `.claude/skills/<名字>/` 这种「下一级就是 skill」的，写 `root` 和 `names`。
   `skills/<名字>/` 这种没有类别的（marketingskills），写 `flat = "skills"`。
   后两种都不要再去扫 `skills/<类别>/`。上游写死的路径放在这条的 `postCopy` 里改。

`skills-update` 会自动把表里所有源一起更新，不用再改它。

名字撞车的话构建会直接失败并报出是哪两个源撞了 —— 这是故意的，
因为这些工具都只按目录名认 skill，悄悄覆盖比构建失败难查得多。
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

**还要数一遍数量。** `skills list` 的个数，和每个工具里能看见的个数，要对上。
少了就是和该工具的内建撞了名（见第四节）。`code-review` 就是这么发现的 ——
它在 Claude Code 里既不报错也不出现，只是静悄悄地少一个。
`uupm-design` 在 Grok 里应该和自带的 `design` 同时在。

---

## 十、全部 skill 一览

<!-- BEGIN GENERATED: skills doc -->

> 这张表由 `skills doc` 生成，每次 `nixos-rebuild switch` 自动刷新。
> **别手改**，改动会被下一次生成覆盖；要改就去改生成逻辑
> （`home/agent-skills.nix` 里的 `cmd_doc`）。
>
> 对应的 skill 池：`/nix/store/p9x6xlkjzyxqccin9adwk4ykkzcrlcxq-agent-skills`

| Skill | 调用方式 | 常驻 tok | 调用 tok | 附属 tok | 用途（作者原文 description，这也是模型看到的触发条件） |
|---|---|---:|---:|---:|---|
| `ab-testing` | 模型自动 / 也可手打 | 83 | 3120 | 6171 | "When the user wants to plan, run, or read A/B tests, or asks a judgement call on one: is the result real, can we stop, which version won, is this worth testing at all: sample size, duration, significance, hypotheses, and experiment backlogs. For tracking setup, see analytics. For page-level conversion fixes, see cro." |
| `ad-creative` | 模型自动 / 也可手打 | 102 | 6490 | 55128 | "When the user wants to write or judge ad creative, or asks which ad, hook, or angle to run or kill: headlines, primary text, and variations for Google, Meta, LinkedIn, and TikTok, fresh angles when creative fatigues. Test hypotheses name the metric, comparison, and expected direction. No AI tells like 'it's not X, it's Y'. For campaign strategy, see ads. For landing pages, see copywriting." |
| `ads` | 模型自动 / 也可手打 | 104 | 7359 | 40904 | "When the user wants to plan, run, or fix paid ads on Google, Meta, and LinkedIn, or asks a judgement call on them: are ads worth it, which channel or budget split, why CPA rose, kill or keep a campaign. End with facts, hypotheses, and missing data; label unavailable inputs MISSING instead of estimating. For ad copy, see ad-creative. For pixels and CAPI, see conversion-tracking. For landing pages, see cro." |
| `ai-seo` | 模型自动 / 也可手打 | 86 | 8929 | 37490 | "When the user wants to get cited and recommended in AI answers (ChatGPT, Perplexity, AI Overviews), or asks why AI cites a competitor, which content gets cited, or whether llms.txt or a page format is worth it: AEO, GEO, AI visibility, agent-readable sites. For technical and on-page SEO, see seo-audit. For structured data, see schema." |
| `analytics` | 模型自动 / 也可手打 | 113 | 3388 | 8269 | "When the user wants to set up or audit analytics, or asks whether a metric or number is calculated right, what to track, or how to name events: tracking plans, GA4, GTM, Mixpanel, PostHog, UTMs. Rate metrics divide matching closed windows, never full-period spend by partial-period results. For conversions in ad platforms, see conversion-tracking. For attribution or platforms that over-claim, see attribution. For tests, see ab-testing." |
| `ask-matt` | 打 `/ask-matt` | 23 | 3108 | 1097 | Ask which skill or flow fits your situation. A router over the skills in this repo. |
| `aso` | 模型自动 / 也可手打 | 59 | 3838 | 11471 | "When the user wants to audit or optimize an App Store or Google Play listing, or asks which title, keywords, or screenshots to pick or why downloads are low: subtitle, description, ratings, and comparing listings with competitors." |
| `attribution` | 模型自动 / 也可手打 | 114 | 5550 | 14573 | "When the user wants to work out which marketing drives revenue, or asks whether a channel is really working, which numbers to trust, or how to credit podcasts and dark social: attribution models, platforms that over-claim, MMM, incrementality and holdout tests, self-reported attribution. For tracking and UTMs, see analytics. For pixels and CAPI, see conversion-tracking. For CRM revenue, see revops. For AI search blind spots, see ai-seo." |
| `banner-design` | 模型自动 / 也可手打 | 115 | 1603 | 1249 | "Design banners for social media, ads, website heroes, creative assets, and print. Multiple art direction options with optional generated or supplied visuals. Actions: design, create, generate banner. Platforms: Facebook, Twitter/X, LinkedIn, YouTube, Instagram, Google Display, website hero, print. Styles: minimalist, gradient, bold typography, photo-based, illustrated, geometric, retro, glassmorphism, 3D, neon, duotone, editorial, collage." |
| `brand` | 模型自动 / 也可手打 | 47 | 901 | 26088 | Brand voice, visual identity, messaging frameworks, asset management, brand consistency. Activate for branded content, tone of voice, marketing assets, brand compliance, style guides. |
| `churn-prevention` | 模型自动 / 也可手打 | 71 | 4659 | 8214 | "When the user wants to reduce churn, or asks why customers cancel, whether to offer a discount or pause: cancellation flows, exit surveys, save offers, dunning and failed-payment recovery. For win-back emails, see emails. For in-app upgrade screens, see paywalls." |
| `co-marketing` | 模型自动 / 也可手打 | 88 | 2878 | 4262 | "When the user wants co-marketing partners or joint campaigns, or asks whether a partner fits, a size mismatch matters, or how to split work and leads: integration partners, cross-promotion, co-branded content, joint webinars. For referral programs, see referrals. For launch partnerships, see launch. For running the event, see events." |
| `codebase-design` | 模型自动 / 也可手打 | 70 | 1440 | 1339 | Shared vocabulary for designing deep modules. Use when the user wants to design or improve a module's interface, find deepening opportunities, decide where a seam goes, make code more testable or AI-navigable, or when another skill needs the deep-module vocabulary. |
| `cold-email` | 模型自动 / 也可手打 | 123 | 2888 | 16066 | "When the user wants to write or run B2B cold outbound, or asks whether an opener, reason to reach out, or email works or why nobody replies: cold emails, follow-ups, sending domains, deliverability, LinkedIn, cadences. Send from secondary domains, verify lists first, turn off open tracking, stop every channel when a prospect replies. No AI tells like 'it's not X, it's Y'. For the list, see prospecting. For lifecycle email, see emails. For call scripts, see sales-enablement." |
| `community-marketing` | 模型自动 / 也可手打 | 82 | 2256 | 3375 | "When the user wants to build or grow an online community, or asks whether a community is worth it, where to host it, or why members stay quiet: Discord, Slack, forums, participation, community-led growth, advocates. For referral programs, see referrals. For creator partnerships, see influencer-marketing." |
| `competitor-profiling` | 模型自动 / 也可手打 | 113 | 4188 | 6592 | "When the user wants to research competitors into dated profiles, or asks what a rival charges, claims, or is doing, or whether a conclusion about them is fair: positioning, pricing, features, reviews, SEO, observed facts kept apart from inference. For comparison pages, see competitors. For battle cards, see sales-enablement. For accounts you sell to, see prospecting. For how a competitor grew, see reverse-engineer-marketing." |
| `competitors` | 模型自动 / 也可手打 | 86 | 2776 | 5633 | "When the user wants to create or audit comparison and alternative pages ('X vs Y', 'X alternative', 'best X alternatives'), or asks what a public page may say about a competitor: page formats, fair claims, and outdated pages. For researching competitors, see competitor-profiling. For internal battle cards, see sales-enablement." |
| `content-strategy` | 模型自动 / 也可手打 | 82 | 4620 | 6088 | "When the user wants to plan content, or asks which topic or piece to prioritize, what to write about, or why posts bring no customers: topic clusters, editorial calendars, roadmaps tied to customers and search. For writing pieces, see copywriting. For SEO audits, see seo-audit. For social content, see social." |
| `conversion-tracking` | 模型自动 / 也可手打 | 121 | 7482 | 155993 | "When the user wants to set up, audit, or fix conversion tracking to Google Ads, Meta, GA4, LinkedIn, and TikTok, or asks why conversions are missing or doubled: GTM, pixels, CAPI, Enhanced Conversions, offline imports. Fire on confirmed success, not the submit click; verify a test conversion arrives; diagnose before changing; offer free paths and disclose partner tools. For tracking plans, see analytics. For attribution, see attribution. For bidding, see ads." |
| `copy-editing` | 模型自动 / 也可手打 | 101 | 4370 | 7327 | "When the user wants to edit, tighten, proofread, or refresh existing copy, or asks whether to keep, cut, or change a line in it, without rewriting from scratch. Every edit removes AI tells: 'it's not X, it's Y' reveals, 'no X, no Y, no Z' lists, and sentences that trail into extra comma clauses. A request to fix one line gets a point edit to that line only. For new copy, see copywriting." |
| `copywriting` | 模型自动 / 也可手打 | 123 | 3620 | 13443 | "When the user wants to write or rewrite page copy (homepage, landing, pricing, feature), or asks which headline, promise, or message to lead with. Diagnoses the input first (blank brief, real voice, or point edit) and changes only what it calls for. Claims must be supportable; a declined claim names the evidence that would unlock it. No AI tells like 'it's not X, it's Y' or 'no X, no Y, no Z'. For editing, see copy-editing. For emails, see emails. For the offer, see offers." |
| `cro` | 模型自动 / 也可手打 | 91 | 1599 | 6460 | "When the user wants more conversions from a page or form, or asks why a page isn't converting, what to change first, or whether to add or remove a field or element: landing and pricing pages, lead forms, or a URL shared for feedback. For signup flows, see signup. For activation, see onboarding. For popups, see popups. For running the test, see ab-testing." |
| `customer-research` | 模型自动 / 也可手打 | 88 | 3511 | 9357 | "When the user wants to run or synthesize customer research, or asks what customer quotes, reviews, or feedback really mean, what is safe to conclude, and what to ask next: interviews, surveys, voice of customer, personas, JTBD, mining Reddit and reviews. For copy from research, see copywriting. For acting on it in pages, see cro." |
| `design-system` | 模型自动 / 也可手打 | 73 | 1751 | 44471 | Token architecture, component specifications, and slide generation. Three-layer tokens (primitive→semantic→component), CSS variables, spacing/typography scales, component specs, strategic slide creation. Use for design tokens, systematic design, brand-compliant presentations. |
| `diagnosing-bugs` | 模型自动 / 也可手打 | 43 | 2116 | 355 | Diagnosis loop for hard bugs and performance regressions. Use when the user says "diagnose"/"debug this", or reports something broken/throwing/failing/slow. |
| `directory-submissions` | 模型自动 / 也可手打 | 91 | 7782 | 21434 | "When the user wants to list a product in startup, SaaS, AI, MCP, and review directories, or asks which directories are worth it or whether listings are working: Product Hunt, G2, Capterra, AlternativeTo, MCP registries, awesome lists, and a submission tracker. For the broader launch, see launch. For other link building, see link-building." |
| `domain-modeling` | 模型自动 / 也可手打 | 42 | 757 | 1284 | Build and sharpen a project's domain model. Use when discussing codebase terminology, writing or editing a GLOSSARY.md, or recording or editing an ADR. |
| `emails` | 模型自动 / 也可手打 | 96 | 2694 | 6991 | "When the user wants to create or improve automated email sequences, or asks what to send, when, or whether an email or flow is working: welcome, onboarding, nurture, and win-back flows. No AI tells like 'it's not X, it's Y', 'no X, no Y, no Z' lists, or fake 'Re:' subject lines. For cold outreach, see cold-email. For in-app onboarding, see onboarding. For texts, see sms." |
| `events` | 模型自动 / 也可手打 | 97 | 2772 | 9736 | "When the user wants to plan, run, sponsor, or speak at events, or asks whether an event or booth is worth the money: webinars, conferences, booths, meetups, show-up rates, and follow-up into pipeline. For launches, see launch. For joint webinars, see co-marketing. For community programs, see community-marketing. For podcasts, see public-relations. For event emails, see emails." |
| `free-tools` | 模型自动 / 也可手打 | 70 | 1673 | 4107 | "When the user wants to plan or build a free tool as marketing, or asks whether a tool idea is worth building or which one to pick: calculators, graders, generators, and other interactive tools for leads, SEO, and links. For downloadable lead magnets, see lead-magnets." |
| `grill-me` | 打 `/grill-me` | 15 | 10 | 35 | A relentless interview to sharpen a plan or design. |
| `grill-with-docs` | 打 `/grill-with-docs` | 31 | 17 | 37 | A relentless interview to sharpen a plan or design, which also creates docs (ADR's and glossary) as we go. |
| `grilling` | 模型自动 / 也可手打 | 40 | 469 | 29 | Grill the user relentlessly about a plan, decision, or idea. Use when the user wants to stress-test their thinking, or uses any 'grill' trigger phrases. |
| `handoff` | 打 `/handoff` | 24 | 183 | 36 | Compact the current conversation into a handoff document for another agent to pick up. |
| `image` | 模型自动 / 也可手打 | 68 | 3771 | 3800 | "When the user wants to create, generate, edit, or optimize marketing images, or asks which approach to take (generate, design, or photograph): blog heroes, social graphics, product mockups, banners, OG images. For ad images, see ad-creative. For video, see video." |
| `implement` | 打 `/implement` | 18 | 123 | 35 | "Implement a piece of work based on a spec or set of tickets." |
| `implement-spec` | 打 `/implement-spec` | 19 | 676 | 42 | "Implement the result of /to-spec and /to-tickets in code." |
| `improve-codebase-architecture` | 打 `/improve-codebase-architecture` | 39 | 1453 | 1702 | Scan a codebase for deepening opportunities, present them as a visual HTML report, then grill through whichever one you pick. |
| `influencer-marketing` | 模型自动 / 也可手打 | 101 | 4786 | 10324 | "When the user wants creator, influencer, or ambassador partnerships, or asks which creators fit, what to pay, which rights to buy, or whether a sponsorship worked: vetting, contracts, briefs, UGC, newsletter and podcast sponsorships, FTC disclosure. For affiliate payouts, see referrals. For community advocacy, see community-marketing. For creator content as ads, see ad-creative." |
| `launch` | 模型自动 / 也可手打 | 79 | 3741 | 4766 | "When the user wants to plan a product or feature launch, or asks whether it's ready, when to announce, or how to get noticed: Product Hunt, beta and early access, waitlists, release go-to-market, launch checklists, release notes. For marketing after launch, see marketing-ideas. For the offer, see offers." |
| `lead-magnets` | 模型自动 / 也可手打 | 86 | 2611 | 9478 | "When the user wants to plan or improve a lead magnet, or asks what to give away for emails or how much to ask in return (gating, form fields): checklists, templates, ebooks, gated guides, content upgrades. For interactive tools, see free-tools. For the follow-up sequence, see emails. For popups that capture emails, see popups." |
| `link-building` | 模型自动 / 也可手打 | 122 | 3209 | 5554 | "When the user wants backlinks and mentions that lift rankings and AI citations, or asks how to get sites to link or whether a link tactic is safe: link gaps, unlinked mentions, broken links, guest posts, best-of outreach. Never buy links that pass ranking credit: paid or exchanged placements get rel=sponsored or nofollow. For press, see public-relations. For directories, see directory-submissions. For reviews, see referrals. For communities, see community-marketing." |
| `marketing-council` | 模型自动 / 也可手打 | 88 | 2873 | 14650 | "When the user wants several expert takes on a marketing decision, or asks what a famous marketer would say about it: a simulated board (Seth Godin, David Ogilvy, April Dunford, Byron Sharp, and more), each grounded in their documented frameworks, where they disagree, and a recommendation. To execute, hand off to the relevant skill." |
| `marketing-ideas` | 模型自动 / 也可手打 | 89 | 1314 | 6981 | "When the user wants marketing ideas or growth tactics for a software product, or asks what to try to get attention or the next customers with little time or budget, or after the obvious channels. Draws on a library of 139 ideas. For a specific channel, see that skill (ads, social, emails, and others). For a full plan, see marketing-plan." |
| `marketing-loops` | 模型自动 / 也可手打 | 81 | 2287 | 28787 | "When the user wants a recurring marketing job an AI agent runs on a cadence or trigger, or asks what a weekly or daily automated check should do, remember, and when it should stop: SEO and ads checks, churn watches, outbound triage. For one-off ideas, see marketing-ideas. For the test loop, see ab-testing." |
| `marketing-plan` | 模型自动 / 也可手打 | 90 | 6017 | 61379 | "When the user wants a full marketing or go-to-market plan for a client, an advised company, or their own product, or asks how to sequence or prioritize several initiatives with a fixed team and budget: channels, budget, team, goals across AARRR, market sizing. For positioning first, see product-marketing. For ideas only, see marketing-ideas." |
| `marketing-psychology` | 模型自动 / 也可手打 | 84 | 5290 | 1509 | "When the user wants to apply psychology to marketing, or asks why buyers behave or value things as they do, or whether a persuasion tactic is honest: biases, mental models, anchoring, social proof, scarcity, loss aversion, framing. For a page, see cro. For pricing tactics, see pricing. For copy, see copywriting." |
| `matt-code-review` | 模型自动 / 也可手打 | 110 | 1558 | 25 | "Review the changes since a fixed point (commit, branch, tag, or merge-base) along two axes: Standards (does the code follow this repo's documented coding standards?) and Spec (does the code match what the originating issue/spec asked for?). Runs both reviews in parallel sub-agents and reports them side by side. Use when the user wants to review a branch, a PR, work-in-progress changes, or asks to \"review since X\"." |
| `offers` | 模型自动 / 也可手打 | 109 | 2222 | 17933 | "When the user wants to design or improve the offer itself, or asks why it isn't selling or how to add urgency honestly: value stacking, bonuses, guarantees, scarcity, payment plans, upsells. Best for services, courses, coaching, and high-ticket B2B; for self-serve SaaS, read pricing first. For price and tiers, see pricing. For the page, see copywriting. For the launch, see launch. For sales collateral, see sales-enablement." |
| `onboarding` | 模型自动 / 也可手打 | 72 | 2708 | 5819 | "When the user wants better onboarding and activation, or asks why new users don't stick or what the first session should do: first-run experience, aha moments, checklists, empty states, time to value. For the signup flow itself, see signup. For onboarding emails, see emails." |
| `paywalls` | 模型自动 / 也可手打 | 89 | 1339 | 4837 | "When the user wants to create or improve in-app paywalls and upgrade moments, or asks when or how hard to ask free users to pay (after they've seen value): upgrade screens, upsell modals, feature gates, limit-reached and trial-expired screens, mobile subscription paywalls. For public pricing pages, see cro. For pricing decisions, see pricing." |
| `popups` | 模型自动 / 也可手打 | 69 | 2796 | 1647 | "When the user wants to create or improve popups, modals, slide-ins, sticky bars, and banners, or asks whether one will help or annoy and when to show it: exit intent, email capture, scroll and time triggers, announcements. For forms and pages outside popups, see cro." |
| `pr` | 模型自动 / 也可手打 | 8 | 965 | 175 | "Use when writing a PR body." |
| `pricing` | 模型自动 / 也可手打 | 87 | 3115 | 9284 | "When the user wants to set pricing and packaging, or asks what to charge, whether to raise prices, or how to move existing customers: tiers, value metrics, per-seat vs usage, freemium and trials, willingness to pay, pricing pages. For in-app upgrade screens, see paywalls. For offers on services, courses, and high-ticket B2B, see offers." |
| `product-marketing` | 模型自动 / 也可手打 | 98 | 3270 | 3894 | "When the user wants to create or update the product marketing context doc (.agents/product-marketing.md), or asks what belongs in it or whether positioning or ICP is clear enough: product, ICP, positioning, competitors, customer language, brand voice. Use it before other marketing skills on a new project, when the audience or positioning changes, and to log learnings." |
| `programmatic-seo` | 模型自动 / 也可手打 | 77 | 1746 | 5538 | "When the user wants SEO pages at scale from templates and data, or asks whether a page set will rank or look thin: location, integration, comparison, directory, and '[X] for [Y]' pages, each useful rather than thin. For SEO audits, see seo-audit. For content planning, see content-strategy." |
| `prospecting` | 模型自动 / 也可手打 | 112 | 4788 | 25491 | "When the user wants to find and qualify prospects for outbound, or asks who to target first, which signal to prioritize, or where to spot buyers with the problem: buying signals, enrichment, verification, account research. Verify emails before a sequence, never scrape LinkedIn: define audiences in Sales Navigator and pull contacts from licensed data. For outreach, see cold-email. For competitor research, see competitor-profiling." |
| `prototype` | 模型自动 / 也可手打 | 47 | 677 | 3263 | Build a throwaway prototype to answer a design question. Use when the user wants to sanity-check whether a state model or logic feels right, or explore what a UI should look like. |
| `public-relations` | 模型自动 / 也可手打 | 100 | 2189 | 16521 | "When the user wants press and media coverage, or asks what to say to a reporter, whether a story is newsworthy, or how to handle a crisis: pitches, press releases, media lists, HARO, op-eds, podcast guest prep, newsjacking (public relations, not pull requests). For directories, see directory-submissions. For launches, see launch. For cold outreach to prospects, see cold-email." |
| `referrals` | 模型自动 / 也可手打 | 84 | 2436 | 14259 | "When the user wants referral and affiliate programs or word of mouth, or asks what to reward, how much to pay, or which loop to start with: refer-a-friend incentives, commissions and payouts, partner programs, 'made with' badges, review campaigns. For launch virality, see launch. For creator deals, see influencer-marketing." |
| `research` | 模型自动 / 也可手打 | 62 | 140 | 24 | Investigate a question against high-trust primary sources and capture the findings as a Markdown file in the repo. Use when the user wants a topic researched, docs or API facts gathered, or reading legwork delegated to a background agent. |
| `retro` | 打 `/retro` | 13 | 1065 | 37 | "Conduct a retrospective on a coding session." |
| `reverse-engineer-marketing` | 模型自动 / 也可手打 | 113 | 6626 | 104305 | "When the user wants to know how another company grew and what to copy, or asks what a competitor did and when: a dated log of their moves against their traffic from public data, archives, job posts, reviews, and their funnel, compared with the user's data, ending in plays routed to other skills. Also finds where competitors are weak. For a snapshot profile, see competitor-profiling. For comparison pages, see competitors." |
| `revops` | 模型自动 / 也可手打 | 76 | 3966 | 12473 | "When the user wants to design revenue operations, or asks when a lead is ready for sales or why sales and marketing disagree on lead quality: lifecycle stages, MQL and SQL, scoring, routing, handoff, pipeline stages, CRM automation. For outbound copy, see cold-email. For email flows, see emails." |
| `sales-enablement` | 模型自动 / 也可手打 | 107 | 4969 | 14709 | "When the user wants sales collateral, or asks what to give a champion or rep, or how to answer an objection or make the case: decks, one-pagers, objection handling, demo scripts, talk tracks, battle cards, proposals, win-loss. For public comparison pages, see competitors. For buyer research, see customer-research. For website copy, see copywriting. For cold emails, see cold-email. For the offer, see offers." |
| `schema` | 模型自动 / 也可手打 | 81 | 1634 | 4779 | "When the user wants to add, fix, or validate schema markup (JSON-LD), or asks which type fits a page or whether some markup is allowed: product, review, recipe, FAQ, rich result eligibility (FAQ no longer earns Google rich results), Search Console errors. For broader SEO, see seo-audit. For AI search, see ai-seo." |
| `seo-audit` | 模型自动 / 也可手打 | 104 | 4321 | 15611 | "When the user wants to audit or diagnose SEO, or asks why traffic dropped, a page won't rank, or whether a setup like canonicals, hreflang, or redirects is right: technical SEO, indexing, Google updates, on-page and titles, Core Web Vitals, local SEO. Start here when someone just says their SEO is bad. For pages at scale, see programmatic-seo. For structured data, see schema. For AI search, see ai-seo." |
| `setup-matt-pocock-skills` | 打 `/setup-matt-pocock-skills` | 52 | 1815 | 3531 | "Configure this repo for the engineering skills: set up its issue tracker, triage label vocabulary, and domain doc layout. Run once before first use of the other engineering skills." |
| `signup` | 模型自动 / 也可手打 | 73 | 2522 | 1561 | "When the user wants better signup, registration, and trial start flows, or asks which fields or steps to cut or whether to require a card: SSO and drop-off before an account exists. For what happens after signup, see onboarding. For lead forms that don't create an account, see cro." |
| `site-architecture` | 模型自动 / 也可手打 | 72 | 3257 | 10895 | "When the user wants to plan or restructure a website, or asks which pages they need or where something belongs: hierarchy, navigation, URL structure, internal linking, website builders and migrations. Not XML sitemaps (see seo-audit). For structured data, see schema." |
| `slides` | 模型自动 / 也可手打 | 37 | 364 | 4526 | Create strategic HTML presentations with Chart.js, design tokens, responsive layouts, copywriting formulas, and contextual slide strategies. |
| `sms` | 模型自动 / 也可手打 | 75 | 4372 | 13058 | "When the user wants SMS, MMS, or WhatsApp marketing, or asks whether texting is worth it or a message is allowed: abandoned cart, win-back, and promo texts, WhatsApp templates and windows, TCPA and A2P 10DLC compliance, SMS vs email. For email, see emails. For phone capture popups, see popups." |
| `social` | 模型自动 / 也可手打 | 109 | 4452 | 22508 | "When the user wants organic social content for LinkedIn, X, Instagram, TikTok, or Facebook, or asks what to post, which format to favor, or from which account: posts, threads, carousels, short-form video scripts, calendars, build-in-public posts from commits, listening. No AI tells like 'it's not X, it's Y' or broetry. For content strategy, see content-strategy. For paid ads, see ad-creative. For press, see public-relations." |
| `tdd` | 模型自动 / 也可手打 | 38 | 860 | 946 | Test-driven development. Use when the user wants to build features or fix bugs test-first, mentions "red-green-refactor", or wants integration tests. |
| `teach` | 打 `/teach` | 17 | 2389 | 2118 | Teach the user a new skill or concept, within this workspace. |
| `ui-styling` | 模型自动 / 也可手打 | 125 | 2580 | 1437709 | Create beautiful, accessible user interfaces with shadcn/ui components (built on Radix UI + Tailwind), Tailwind CSS utility-first styling, and canvas-based visual designs. Use when building user interfaces, implementing design systems, creating responsive layouts, adding accessible components (dialogs, dropdowns, forms, tables), customizing themes and colors, implementing dark mode, generating visual designs and posters, or establishing consistent styling patterns across applications. |
| `ui-ux-pro-max` | 模型自动 / 也可手打 | 128 | 4004 | 898532 | "UI/UX design intelligence for web, mobile, and desktop. This skill should be used when designing, building, reviewing, or fixing interfaces, including pages, components, design systems, accessibility, interaction, responsive layout, typography, color, charts, and stack-specific UI implementation. Searchable local data: 80 searchable styles (51 active), 192 product palettes and reasoning profiles, 74 font pairings, 120 UX guidelines, 105 icons, 17 GSAP presets, 25 chart types, and 22 stacks." |
| `uupm-design` | 模型自动 / 也可手打 | 163 | 3339 | 69061 | "Comprehensive design skill: brand identity, design tokens, UI styling, logo generation (55 styles, Gemini, Atlas Cloud, or MuAPI AI), corporate identity program (50 deliverables, CIP mockups), HTML presentations (Chart.js), banner design (22 styles, social/ads/web/print), icon design (15 styles, SVG, Gemini 3.1 Pro), social photos (HTML→screenshot, multi-platform). Actions: design logo, create CIP, generate mockups, build slides, design banner, generate icon, create social photos, social media images, brand identity, design system. Platforms: Facebook, Twitter, LinkedIn, YouTube, Instagram, Pinterest, TikTok, Threads, Google Ads." |
| `video` | 模型自动 / 也可手打 | 83 | 4085 | 11720 | "When the user wants to create video with AI tools or code, or asks which approach to use (screen recording, AI avatar, generated, or templated) or how to make videos repeatably: product demos, AI generation (Veo, Sora, HeyGen), programmatic video with Remotion. For what to post, see social. For video ads, see ad-creative." |
| `wait-what` | 打 `/wait-what` | 16 | 69 | 40 | "Stop. That last message did not land: re-pitch it." |
| `wizard` | 模型自动 / 也可手打 | 80 | 942 | 2399 | Generate an interactive bash wizard that walks a human through steps only they can perform. Use when provisioning infrastructure, setting up credentials or CI secrets, walking an unfamiliar third-party dashboard, or running a one-off migration or cutover. Don't invoke this for steps the agent can perform itself. |
| `writing-for-agents` | 模型自动 / 也可手打 | 31 | 2683 | 683 | Writing documents for agents. Use when creating or editing skills, or modifying AGENTS.md or CLAUDE.md. |

合计 **82** 个 skill：常驻 ≈ **6358 tokens**（每个会话都付），正文全加起来 ≈ 239179 tokens，附属文件另计 ≈ 3423987 tokens。

token 数是字符数 ÷ 4 的英文经验估算，误差约 ±15%。

<!-- END GENERATED -->

---

## 相关文档

- [`0010`](0010_CLAUDE_CODE_VERSION_PINNING.md) —— claude-code 本身的版本钉法
- [`0011`](0011_ROOT_OWNED_FILES_IN_REPO.md) —— 为什么 `nix flake update` 永远不加 sudo
- [`000D`](000D_CLAUDE_CODE_IN_NEOVIM.md) —— Neovide 里怎么接入 Claude Code
- [`README.md`](../README.md) —— 「Agent Skills」一节是操作手册版
