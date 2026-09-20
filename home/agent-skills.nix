# ============================================================
# Agent Skills —— 一份 skill，四个 AI 工具共用
# ============================================================
# 背景：SKILL.md 那套（frontmatter + 正文的技能包）在 2025 年底已经变成
# 跨厂商的事实标准，各家认的**全局**目录如下：
#
#   Claude Code            ~/.claude/skills/<名>/SKILL.md   （只认这个）
#   VS Code Copilot        ~/.copilot/skills/ | ~/.claude/skills/ | ~/.agents/skills/
#   Copilot CLI            ~/.copilot/skills/
#   Zed（v1.4.2+）         ~/.agents/skills/
#   Gemini CLI             ~/.gemini/skills/ 或 ~/.agents/skills/（后者优先）
#
# 所以只要把同一份 skill 同时链到下面 TARGETS 里那三个目录，
# 上面所有工具就都能看见。~/.agents/skills 是新工具的汇合点，
# 将来再出编辑器大概率也读它。
#
# 分两层，理由见 README「Agent Skills」一节：
#
#   第一层（声明式，home-manager 管）
#     ~/.local/share/agent-skills -> /nix/store/…-agent-skills/
#     装了哪些 skill、什么版本，全由 flake.lock 钉死。
#
#   第二层（可变状态，skills 命令管）
#     ~/.claude/skills/<名> -> ~/.local/share/agent-skills/<名>
#     开关状态存 ~/.local/state/agent-skills/disabled。
#
# 为什么要分两层：`skills off tdd` 如果去动 home-manager 管的链接，
# 下一次 nixos-rebuild 会把它**悄悄装回来**。把「有哪些」和「开哪些」
# 拆开之后，禁用状态能活过 rebuild，而新机器第一次 build 完是全开的 ——
# 可复现性一点没丢。
#
# 注意：第二层那些链接不在 home-manager 的账本上。这是有意的取舍，
# 代价是 home-manager 不会替你清理它们 —— 清理由 `skills sync` 负责，
# 它只动「原始链接目标落在 pool 里」的符号链接，不碰你手写的 skill，
# 也不碰 ~/.claude/skills/synced/（那是 Claude 云端同步的真目录）。
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  # flake 里 nixosConfigurations 的属性名。
  # 注意它不是 networking.hostName（那个是 thinkpad-nixos）。
  # 和 home/toru.nix 里 nrb / ncheck 等别名硬编码的是同一个东西，
  # 加新机器时这两处要一起改。
  nixosHost = "thinkpad";

  # ============================================================
  # skill 源
  # ============================================================
  # 加一个新源：flake.nix 里加一个 `flake = false` 的 input，
  # 再在这张表里加一条，两处都要改。skills-update 会把表里所有源
  # 一起 nix flake update。
  #
  # categories：源仓库把 skill 按 skills/<类别>/<名字>/SKILL.md 分目录放，
  #   这里列出要装的类别，装的时候会**拍平**成 <名字>/SKILL.md ——
  #   因为四家工具都只认「skills 目录下一级就是 skill 名」，不递归。
  # exclude：类别里个别不要的。
  # rename：装进去的时候换个名字，**目录名和 frontmatter 的 `name:` 一起改**。
  #   只改目录名不够 —— 各家工具认 skill 的依据不完全一样，Claude Code 按
  #   目录名，别家可能按 frontmatter，两边不一致会出现「目录叫 A、工具里
  #   显示成 B」的错位，比撞名本身更难查。
  #
  # mattpocock 的 in-progress/ 和 misc/ 两个类别故意不装：前者是作者自己
  # 标了半成品的；后者里的 git-guardrails-claude-code 会和本仓库 CLAUDE.md
  # 「不要自动提交」的约定抢同一件事的管辖权，两套规则管一件事最难查。
  skillSources = {
    matt-pocock = {
      input = "matt-skills";
      src = inputs.matt-skills;
      categories = [
        "engineering"
        "productivity"
      ];
      exclude = [ ];
      rename = {
        # Claude Code 自带一个内建的 code-review（`/code-review`，云端多
        # agent 审查），同名时内建赢：文件装上了，但在 Claude Code 里
        # 根本够不着。其它工具没有这个内建，于是同一个名字在不同工具里
        # 指向两个不同的东西 —— 比「用不了」更坑，所以直接改名避开。
        #
        # 注意这种撞车只有运行时才知道，构建期的撞名检查只管源与源之间，
        # 查不到「和工具内建撞」。以后装别的 skill 集合时留意这一点。
        code-review = "matt-code-review";
      };
    };
  };

  updateInputs = lib.unique (lib.mapAttrsToList (_: s: s.input) skillSources);

  # ============================================================
  # skill 池：把所有源拍平进一个 store 路径
  # ============================================================
  pool = pkgs.runCommand "agent-skills" { } (
    ''
      mkdir -p "$out"
      : > "$out/.manifest"
    ''
    + lib.concatStrings (
      lib.mapAttrsToList (
        sname: s:
        lib.concatMapStrings (cat: ''
          for d in ${s.src}/skills/${cat}/*/; do
            n=$(basename "$d")
            # 没有 SKILL.md 的目录不是 skill（比如类别自己的 README）
            [ -f "$d/SKILL.md" ] || continue
            case " ${lib.concatStringsSep " " s.exclude} " in
              *" $n "*) continue ;;
            esac
            target="$n"
            case "$n" in
              ${lib.concatStrings (
                lib.mapAttrsToList (from: to: ''
                  ${from}) target=${to} ;;
                '') s.rename
              )}
            esac
            if [ -e "$out/$target" ]; then
              echo "agent-skills: skill 名字冲突：$target（${sname}/${cat} 和已有的撞了）" >&2
              exit 1
            fi
            cp -r "$d" "$out/$target"
            chmod -R u+w "$out/$target"
            # 改名的话 frontmatter 的 name 也要跟着改，只改目录名会错位。
            if [ "$target" != "$n" ]; then
              awk -v new="$target" '
                NR == 1 && /^---$/  { print; inside = 1; next }
                inside && /^---$/   { inside = 0; print; next }
                inside && /^name:/  { print "name: " new; next }
                                    { print }
              ' "$d/SKILL.md" > "$out/$target/SKILL.md"
            fi
            printf '%s\t%s\t%s\t%s\n' "$target" "${sname}" "${cat}" "$n" \
              >> "$out/.manifest"
          done
        '') s.categories
      ) skillSources
    )
  );

  # ============================================================
  # skills：开关 + 查看 + 生成指南
  # ============================================================
  skillsPath = lib.makeBinPath (
    with pkgs;
    [
      coreutils
      findutils
      gnugrep
      gawk
      gnused
      diffutils
    ]
  );

  updatePath = lib.makeBinPath (
    with pkgs;
    [
      coreutils
      jq
    ]
  );

  # 这里用 writeShellScriptBin 而不是 writeShellApplication。
  # 后者会在构建时跑 shellcheck，而 shellcheck 在构建沙箱的 C locale 下
  # **打印不出中文**：一旦它有话要说，就直接崩在
  # "commitBuffer: invalid argument (cannot encode character)" 上，
  # 报错里完全看不出原始问题是什么 —— 而这两个脚本通篇都是中文提示。
  # 脚本本身是手工验证过的，改完请实机跑一遍 `skills list` / `skills status`。
  # 注意：脚本正文每一行都保持同样的缩进。里面有 <<'USAGE' / <<EOF 这种
  # 非缩进 heredoc，终止符必须落在行首；nix 的 '' 字符串是按**最小缩进**
  # 统一剥离的，缩进一旦不齐，终止符前面就会多出空格，heredoc 直接不闭合。
  skillsCmd = pkgs.writeShellScriptBin "skills" ''
    set -euo pipefail
    export PATH="${skillsPath}:$PATH"

    POOL="$HOME/.local/share/agent-skills"
    STATE_DIR="$HOME/.local/state/agent-skills"
    DISABLED="$STATE_DIR/disabled"
    REPO="''${NIXOS_CONFIG_DIR:-${config.home.homeDirectory}/nixos-config}"
    GUIDE="$REPO/Lesson-Learn/0012_AGENT_SKILLS.md"
    BEGIN_MARK="<!-- BEGIN GENERATED: skills doc -->"
    END_MARK="<!-- END GENERATED -->"

    # 四家工具认的全局 skill 目录（见本文件头注释）
    TARGETS=(
      "$HOME/.claude/skills"
      "$HOME/.agents/skills"
      "$HOME/.copilot/skills"
    )

    die() {
      printf 'skills: %s\n' "$*" >&2
      exit 1
    }

    usage() {
      cat <<'USAGE'
    用法: skills <子命令>

      list              列出所有 skill：调用方式、token 估算、开关状态
      status            看 pool 指向哪个 store 路径、四个目录的链接是否健康
      on  <名字…|--all> 启用，立刻对所有工具生效
      off <名字…|--all> 禁用，状态存在 ~/.local/state/agent-skills/disabled，
                        活得过 nixos-rebuild
      sync              按当前开关状态重建符号链接
                        （home-manager 激活时自动跑，平时不用手动执行）
      doc [--quiet]     重新生成使用指南里的表格

    升级 skill 用另一个命令：skills-update
    USAGE
    }

    have_pool() {
      [ -d "$POOL" ] || die "找不到 skill 池 $POOL，先跑一次 nixos-rebuild switch"
    }

    ensure_state() {
      mkdir -p "$STATE_DIR"
      [ -f "$DISABLED" ] || : > "$DISABLED"
    }

    # pool 里的一级目录名 = skill 名
    skill_names() {
      find -L "$POOL" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | LC_ALL=C sort
    }

    # fm <skill> <frontmatter 字段名>
    fm() {
      awk -v f="$2" '
        NR == 1 && /^---$/ { inside = 1; next }
        inside && /^---$/   { exit }
        inside && index($0, f ":") == 1 {
          sub("^" f ":[ \t]*", "")
          print
          exit
        }
      ' "$POOL/$1/SKILL.md"
    }

    # 带 disable-model-invocation: true 的是「只能手动 /名字 调用」。
    # 注意这是 Claude Code 专属字段，Zed / Copilot / Gemini 多半不认，
    # 在那些工具里这些 skill 同样可能被模型自己捡起来。
    is_manual() {
      [ -n "$(fm "$1" disable-model-invocation)" ]
    }

    # 常驻成本：name + description，每个会话都会注入
    catalog_chars() {
      local d
      d="$(fm "$1" description)"
      printf '%s' "$(( ''${#1} + ''${#d} ))"
    }

    # 调用成本：SKILL.md 去掉 frontmatter 之后的正文
    body_chars() {
      awk '
        NR == 1 && /^---$/ { inside = 1; next }
        inside && /^---$/   { inside = 0; next }
        !inside             { n += length($0) + 1 }
        END                 { print n + 0 }
      ' "$POOL/$1/SKILL.md"
    }

    # 附属文件：正文指示时才会再读的 .md / .sh / .yaml
    extra_bytes() {
      find -L "$POOL/$1" -type f ! -name SKILL.md -printf '%s\n' \
        | awk '{ s += $1 } END { print s + 0 }'
    }

    # 字符数 ÷ 4 的英文经验值，误差约 ±15%。要精确值得调
    # Anthropic 的 count_tokens API（要 key、要联网、要计费），
    # 换算就改这一个函数。
    tok() {
      local c
      c="$1"
      printf '%s' "$(( ( c + 3 ) / 4 ))"
    }

    is_disabled() {
      [ -f "$DISABLED" ] && grep -qxF -- "$1" "$DISABLED"
    }

    require_skill() {
      [ -d "$POOL/$1" ] || die "没有这个 skill：$1（skills list 看全部）"
    }

    # ---------- sync ----------
    cmd_sync() {
      have_pool
      ensure_state
      local t l n
      for t in "''${TARGETS[@]}"; do
        mkdir -p "$t"
        # 先剪枝。判据用**原始** readlink 而不是 readlink -f：
        # pool 自己就是指向 /nix/store 的符号链接，-f 会把它解析掉，
        # 匹配不上；而且换了 store 路径之后的断链也要能剪掉。
        for l in "$t"/*; do
          [ -L "$l" ] || continue
          case "$(readlink "$l")" in
            "$POOL"/*) rm -f "$l" ;;
          esac
        done
        # 再按开关状态建链
        while IFS= read -r n; do
          if is_disabled "$n"; then continue; fi
          ln -sfn "$POOL/$n" "$t/$n"
        done < <(skill_names)
      done
    }

    # ---------- list ----------
    cmd_list() {
      have_pool
      local n mode st cc bc eb tc tb te total off
      total=0
      off=0
      tc=0
      tb=0
      te=0
      printf '%-32s %-7s %-5s %9s %9s %9s\n' \
        NAME INVOKE STATE CAT-TOK BODY-TOK EXTRA-TOK
      while IFS= read -r n; do
        if is_manual "$n"; then mode="manual"; else mode="auto"; fi
        if is_disabled "$n"; then st="off"; off=$(( off + 1 )); else st="on"; fi
        cc=$(catalog_chars "$n")
        bc=$(body_chars "$n")
        eb=$(extra_bytes "$n")
        total=$(( total + 1 ))
        if [ "$st" = "on" ]; then
          tc=$(( tc + cc ))
          tb=$(( tb + bc ))
          te=$(( te + eb ))
        fi
        printf '%-32s %-7s %-5s %9s %9s %9s\n' \
          "$n" "$mode" "$st" "$(tok "$cc")" "$(tok "$bc")" "$(tok "$eb")"
      done < <(skill_names)
      printf '\n'
      printf '共 %s 个，启用 %s，禁用 %s\n' "$total" "$(( total - off ))" "$off"
      printf 'manual = 只能你打 /名字 调用；auto = 模型也能自己捡起来\n'
      printf '启用部分的常驻成本 ≈ %s tokens（每个会话都付）\n' "$(tok "$tc")"
      printf '全部正文若都被触发 ≈ %s tokens；附属文件另计 ≈ %s tokens\n' \
        "$(tok "$tb")" "$(tok "$te")"
      printf 'token 是字符数 ÷ 4 的估算，误差约 ±15%%\n'
    }

    # ---------- status ----------
    cmd_status() {
      have_pool
      local t total off n live broken
      total=$(skill_names | wc -l)
      off=0
      if [ -f "$DISABLED" ]; then
        off=$(grep -c . "$DISABLED" || true)
      fi
      printf 'pool    : %s\n' "$POOL"
      printf '          -> %s\n' "$(readlink -f "$POOL")"
      printf 'state   : %s\n' "$DISABLED"
      printf 'skills  : 共 %s，启用 %s，禁用 %s\n' \
        "$total" "$(( total - off ))" "$off"
      for t in "''${TARGETS[@]}"; do
        live=0
        broken=0
        if [ -d "$t" ]; then
          for n in "$t"/*; do
            [ -L "$n" ] || continue
            case "$(readlink "$n")" in
              "$POOL"/*)
                if [ -e "$n" ]; then live=$(( live + 1 )); else broken=$(( broken + 1 )); fi
                ;;
            esac
          done
          printf '%-24s 本工具可见 %s 个' "$t" "$live"
          if [ "$broken" -gt 0 ]; then
            printf '，断链 %s 个（跑 skills sync 修）' "$broken"
          fi
          printf '\n'
        else
          printf '%-24s 不存在（跑 skills sync 建）\n' "$t"
        fi
      done
    }

    # ---------- on / off ----------
    cmd_off() {
      have_pool
      ensure_state
      [ "$#" -gt 0 ] || die "用法: skills off <名字…|--all>"
      local n
      for n in "$@"; do
        if [ "$n" = "--all" ]; then
          skill_names > "$DISABLED"
          cmd_sync
          printf 'skills: 已全部禁用（skills on --all 开回来）\n'
          return
        fi
      done
      for n in "$@"; do
        require_skill "$n"
      done
      for n in "$@"; do
        if ! is_disabled "$n"; then printf '%s\n' "$n" >> "$DISABLED"; fi
      done
      cmd_sync
      printf 'skills: 已禁用 %s\n' "$*"
    }

    cmd_on() {
      have_pool
      ensure_state
      [ "$#" -gt 0 ] || die "用法: skills on <名字…|--all>"
      local n tmp
      for n in "$@"; do
        if [ "$n" = "--all" ]; then
          : > "$DISABLED"
          cmd_sync
          printf 'skills: 已全部启用\n'
          return
        fi
      done
      for n in "$@"; do
        require_skill "$n"
      done
      tmp="$(mktemp)"
      cp "$DISABLED" "$tmp"
      for n in "$@"; do
        grep -vxF -- "$n" "$tmp" > "$tmp.next" || true
        mv "$tmp.next" "$tmp"
      done
      mv "$tmp" "$DISABLED"
      cmd_sync
      printf 'skills: 已启用 %s\n' "$*"
    }

    # ---------- doc ----------
    # 只写 BEGIN/END 之间那一段，手写的前言原样保留。
    # 刻意不写生成时间、不写开关状态：那样每次 rebuild 都会把仓库弄脏。
    # 这一段只是 pool 的函数 —— 升级了 skill 才会变。
    cmd_doc() {
      have_pool
      local quiet n desc mode cc bc eb tc tb te total tmp
      quiet=0
      if [ "''${1:-}" = "--quiet" ]; then quiet=1; fi

      if [ ! -f "$GUIDE" ]; then
        if [ "$quiet" = 1 ]; then return 0; fi
        die "找不到指南 $GUIDE"
      fi
      if ! grep -qF "$BEGIN_MARK" "$GUIDE"; then
        if [ "$quiet" = 1 ]; then return 0; fi
        die "$GUIDE 里找不到生成标记，手工补一对 BEGIN/END 标记再试"
      fi
      if [ ! -w "$GUIDE" ]; then
        printf 'skills: %s 不可写，跳过生成\n' "$GUIDE" >&2
        return 0
      fi

      total=0
      tc=0
      tb=0
      te=0
      tmp="$(mktemp)"
      {
        printf '\n'
        printf '> 这张表由 `skills doc` 生成，每次 `nixos-rebuild switch` 自动刷新。\n'
        printf '> **别手改**，改动会被下一次生成覆盖；要改就去改生成逻辑\n'
        printf '> （`home/agent-skills.nix` 里的 `cmd_doc`）。\n'
        printf '>\n'
        printf '> 对应的 skill 池：`%s`\n' "$(readlink -f "$POOL")"
        printf '\n'
        printf '| Skill | 调用方式 | 常驻 tok | 调用 tok | 附属 tok | 用途（作者原文 description，这也是模型看到的触发条件） |\n'
        printf '|---|---|---:|---:|---:|---|\n'
        while IFS= read -r n; do
          desc="$(fm "$n" description | sed 's/|/\\|/g')"
          if is_manual "$n"; then mode="打 \`/$n\`"; else mode="模型自动 / 也可手打"; fi
          cc=$(catalog_chars "$n")
          bc=$(body_chars "$n")
          eb=$(extra_bytes "$n")
          total=$(( total + 1 ))
          tc=$(( tc + cc ))
          tb=$(( tb + bc ))
          te=$(( te + eb ))
          printf '| `%s` | %s | %s | %s | %s | %s |\n' \
            "$n" "$mode" "$(tok "$cc")" "$(tok "$bc")" "$(tok "$eb")" "$desc"
        done < <(skill_names)
        printf '\n'
        printf '合计 **%s** 个 skill：常驻 ≈ **%s tokens**（每个会话都付），' \
          "$total" "$(tok "$tc")"
        printf '正文全加起来 ≈ %s tokens，附属文件另计 ≈ %s tokens。\n' \
          "$(tok "$tb")" "$(tok "$te")"
        printf '\n'
        printf 'token 数是字符数 ÷ 4 的英文经验估算，误差约 ±15%%。\n'
        printf '\n'
      } > "$tmp"

      awk -v b="$BEGIN_MARK" -v e="$END_MARK" -v f="$tmp" '
        $0 == b { print; while ((getline line < f) > 0) print line; skip = 1; next }
        $0 == e { skip = 0 }
        !skip   { print }
      ' "$GUIDE" > "$GUIDE.next"

      if cmp -s "$GUIDE" "$GUIDE.next"; then
        rm -f "$GUIDE.next" "$tmp"
        if [ "$quiet" = 0 ]; then printf 'skills: 指南已是最新\n'; fi
      else
        mv "$GUIDE.next" "$GUIDE"
        rm -f "$tmp"
        printf 'skills: 已刷新 %s（记得 git add）\n' "$GUIDE"
      fi
    }

    case "''${1:-}" in
      list)   shift; cmd_list "$@" ;;
      status) shift; cmd_status "$@" ;;
      on)     shift; cmd_on "$@" ;;
      off)    shift; cmd_off "$@" ;;
      sync)   shift; cmd_sync "$@" ;;
      doc)    shift; cmd_doc "$@" ;;
      ""|-h|--help|help) usage ;;
      *) die "未知子命令：$1（skills --help 看用法）" ;;
    esac
  '';

  # ============================================================
  # skills-update：升级 skill 源
  # ============================================================
  # ============================================================
  # skills 的回归测试
  # ============================================================
  # 测试内容和接缝的说明在 home/skills-tests.sh 的文件头。
  # 这里只负责在**构建期**跑一遍：测试不过，skillsTests 就产不出 $out，
  # 下面 skillsGated 引用不到它，整个 home 层构建失败 ——
  # 也就是 `nhm` / `nrb` 会直接停在这，而不是等到运行时才发现误删。
  skillsTests = pkgs.runCommand "skills-tests" { } ''
    export SKILLS_BIN=${skillsCmd}/bin/skills
    export HOME="$TMPDIR/home"
    bash ${./skills-tests.sh}
    touch "$out"
  '';

  # 把测试挂进 skills 的依赖链。单独留一层是因为 writeShellScriptBin 的
  # 产物不好直接加依赖，而「测试不过就装不上」这件事必须是强制的 ——
  # 否则测试只是摆设，没人会记得去跑。
  skillsGated = pkgs.runCommand "skills" { } ''
    test -f ${skillsTests}
    mkdir -p "$out/bin"
    ln -s ${skillsCmd}/bin/skills "$out/bin/skills"
  '';

  skillsUpdateCmd = pkgs.writeShellScriptBin "skills-update" ''
    set -euo pipefail
    export PATH="${updatePath}:$PATH"

    REPO="''${NIXOS_CONFIG_DIR:-${config.home.homeDirectory}/nixos-config}"
    USER_NAME="${config.home.username}"
    INPUTS=(${lib.concatStringsSep " " (map lib.escapeShellArg updateInputs)})

    cd "$REPO" || exit 1

    rev_of() {
      jq -r --arg i "$1" '.nodes[$i].locked.rev // "?"' flake.lock
    }

    declare -A OLD
    for i in "''${INPUTS[@]}"; do
      OLD["$i"]="$(rev_of "$i")"
    done

    # 第 1 步：更新 lock。
    # **绝对不能加 sudo** —— root 往仓库里写 flake.lock 就是 CLAUDE.md 坑 5，
    # 之后 git add 会报 insufficient permission，而且只对部分文件失败。
    printf 'skills-update: nix flake update %s\n' "''${INPUTS[*]}"
    nix flake update "''${INPUTS[@]}"

    changed=0
    for i in "''${INPUTS[@]}"; do
      new="$(rev_of "$i")"
      if [ "$new" = "''${OLD[$i]}" ]; then
        printf '  %-16s 无变化 (%s)\n' "$i" "''${new:0:12}"
      else
        printf '  %-16s %s -> %s\n' "$i" "''${OLD[$i]:0:12}" "''${new:0:12}"
        changed=1
      fi
    done

    if [ "$changed" = 0 ]; then
      printf 'skills-update: 已是最新，不用重建。\n'
      exit 0
    fi

    # 第 2 步：用户态先构建两层（README / CLAUDE.md 重建流程第 3 步）。
    # 求值错误在这里就暴露，不用等到 root 阶段。
    printf '\nskills-update: 用户态构建系统层…\n'
    nix build "$REPO#nixosConfigurations.${nixosHost}.config.system.build.toplevel" \
      --out-link /tmp/res
    printf 'skills-update: 用户态构建 home 层…\n'
    nix build "$REPO#nixosConfigurations.${nixosHost}.config.home-manager.users.$USER_NAME.home.activationPackage" \
      --out-link /tmp/hm

    cat <<EOF

    skills-update: lock 已更新，两层都构建通过。接下来由你决定：

      cd $REPO
      git diff flake.lock                 # 看看升到了哪个版本
      sudo nixos-rebuild switch --flake $REPO#${nixosHost}

    switch 的时候会自动重建符号链接、刷新使用指南
    （Lesson-Learn/0012_AGENT_SKILLS.md，记得连 flake.lock 一起 commit）。
    EOF
  '';
in
{
  # 装 skillsGated 而不是 skillsCmd：前者把回归测试挂在依赖链上。
  home.packages = [
    skillsGated
    skillsUpdateCmd
  ];

  # 第一层：声明式的 skill 池。版本跟着 flake.lock 走。
  home.file.".local/share/agent-skills".source = pool;

  # 第二层：按开关状态把池子里的 skill 链进各工具的目录。
  # 必须排在 linkGeneration 之后 —— 那一步才把上面的 pool 符号链接写好，
  # 早跑的话 sync 读到的还是上一代的池子。
  home.activation.agentSkills = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run ${skillsGated}/bin/skills sync
    run ${skillsGated}/bin/skills doc --quiet || true
  '';
}
