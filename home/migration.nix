{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}:

let
  cfg = config.custom.migration;

  # ============================================
  # B 类状态清单 —— 两个命令共用的单一真相
  # ============================================
  # 路径相对 $HOME。state-sync 按它搬，migration-check 按它查。
  # **不要在任何一个脚本里另写一份** —— 两份清单必然漂移，
  # 而漂移的表现是「换机器之后某个设置莫名其妙没了」，极难联想到这里。
  #
  # 什么该进这个清单，判据见 MIGRATION.md 第 0 节的 A/B/C 三分法：
  # 能进 Nix 的进 Nix（A），进不了但可版本化的进这里（B），
  # 是秘密的一律不进（C，新机器重新签发）。
  stateFiles = [
    # 输入法：启用了哪些、顺序、快捷键、各插件设置
    ".config/fcitx5/profile"
    ".config/fcitx5/config"
    ".config/fcitx5/conf"

    # Mozc 学习历史。**整个目录**，.encrypt_key.db 必须一起 ——
    # .history.db 是加密的，只搬历史不搬密钥等于学习记录全丢。
    ".config/mozc"

    # 零碎 UI 状态
    ".local/state/theme/current" # 当前选的是 20 套主题里哪套
    ".local/state/agent-skills/disabled" # 关掉了哪些 Agent Skill
    ".config/monitors.xml" # 多显示器布局（台式机上有用）
    ".config/user-dirs.dirs" # XDG 目录指向

    # Claude Code 的偏好：当前模型、effort、主题、推送开关。
    #
    # **归 B 类而不是 A 类，是因为 Claude Code 在运行时写它** ——
    # /model、/effort、/config、Remote Control 开关改的都是这个文件。
    # 写成 home.file 的只读符号链接会让那几个命令全部失效，
    # 等于为了声明式的纯度关掉工具的一部分功能。
    #
    # 同目录的 keybindings.json 相反：那是手写的、工具不碰，所以进了 Nix
    # （home/toru.nix 的 home.file）。**同一个目录里两个文件分属两类，
    # 判据是「谁在写这个文件」，不是「它们放在一起」。**
    ".claude/settings.json"
  ];

  # ============================================
  # migration-check 的白名单（~/.claude 下）
  # ============================================
  # 这个目录是混的：两个配置文件 + 凭据 + 一堆运行时状态。
  #
  # **单独扫它而不是整个目录加白名单**，是因为整个忽略的话，
  # 以后 Claude Code 在这里新增一个该管的配置文件就发现不了了 ——
  # 而那正是这个工具要防的事。
  ignoredClaude = [
    # C 类：凭据与会话
    ".credentials.json"
    "sessions"
    "ide"
    "daemon"
    "daemon.log"

    # 运行时状态与缓存，工具自己管
    "history.jsonl"
    "projects"
    "file-history"
    "shell-snapshots"
    "paste-cache"
    "cache"
    "backups"
    "telemetry"
    "jobs"
    "session-env"
    "plugins" # 插件市场的同步缓存
    ".last-cleanup"

    # skills/ 是**混合目录**，两半各有主人，都不需要搬：
    #   <skill名>  -> ~/.local/share/agent-skills/<名> -> store
    #                 我们的 skills sync 建的链接（见 home/agent-skills.nix）
    #   synced/    -> 真实文件，Claude Code 自己从账号同步下来的那批
    #                 （docx / pptx / xlsx / pdf / skill-creator 等）
    #
    # 因为 synced/ 里是真实文件，整个目录过不了 is_managed 的
    # 「每个文件都是 store 链接」判定，所以必须显式列出来。
    #
    # 禁用状态不在这里 —— 那在 ~/.local/state/agent-skills/disabled，
    # 已经收进 B 类了。
    "skills"
  ];

  # ============================================
  # migration-check 的白名单（$HOME 根下）
  # ============================================
  # 家目录根下已知不需要搬的条目。**这一层原先根本没扫** ——
  # 只扫了 ~/.config 和 ~/.local/share，结果 ~/.claude、~/.vscode、
  # ~/.npm、~/.dotnet 这些开发工具留下的配置全在盲区里。
  ignoredHome = [
    # 单独扫的，不在这里重复报
    ".claude"
    ".config"
    ".local"

    # 缓存与运行时状态
    ".cache"
    ".atuin" # 历史库本体，B 类里刻意没收（见 stateFiles 的注释）
    ".bash_history"
    ".zsh_history"
    ".zcompdump"
    ".viminfo"
    ".lesshst"
    ".dotnet"
    ".npm"
    ".pki"
    ".mozilla"
    ".var" # Flatpak 的应用数据，靠 flatpak.nix 声明重建
    ".xwechat"
    ".vscode" # 扩展由上面单独一节查
    ".vscode-shared"

    # C 类：秘密，刻意不搬
    ".ssh"
    ".gnupg"
    ".claude.json" # 里面有 .credentials 之外的会话凭据

    # Nix 自己的
    ".nix-defexpr"
    ".nix-profile"
    "result"

    # XDG 用户目录
    "Desktop"
    "Documents"
    "Downloads"
    "Music"
    "Pictures"
    "Public"
    "Templates"
    "Videos"

    # 工作目录与仓库
    "Projects"
    "nixos-config"
    "dotfiles-state"

    # 杂项
    ".sys1og.conf"
    ".icons"
    ".themes"
  ];

  # ============================================
  # migration-check 的白名单（~/.config 与 ~/.local/share）
  # ============================================
  # 这两个目录下已知不需要搬的条目。
  #
  # **home-manager 管的东西不用列** —— 它们是指向 /nix/store 的符号链接，
  # 脚本按这一点自动跳过。这里只列「真实存在、但确实不用搬」的：
  # 缓存、运行时状态、能自动重建的东西、以及 C 类（秘密）。
  ignored = [
    "BraveSoftware"
    "Code"
    "GIMP"
    "atuin"
    "autostart"
    "burn-my-windows"
    "chromium"
    "dconf"
    "dleyna-server-service.conf"
    "environment.d"
    "epiphany"
    "evolution"
    "fcitx" # fcitx4 的残留 dbus 套接字，现在用的是 fcitx5
    "htop" # 空目录，htop 建了就没写过
    "libreoffice" # 应用自己的状态，一百多个文件，没有搬的价值
    "user-dirs.locale"
    "fontconfig"
    "gh" # C 类：凭据
    "github-copilot" # C 类：凭据
    "gnome-initial-setup-done"
    "goa-1.0"
    "gtk-3.0"
    "gtk-4.0"
    "ibus"
    "monitors.xml~"
    "mozilla"
    "nautilus"
    "peazip"
    "pulse"
    "systemd"
    "ulauncher"
    "zen"
    ".gsd-keyboard.settings-ported"

    # ~/.local/share 下的
    "Trash"
    "agent-skills" # A 类：home-manager 管的符号链接
    "applications"
    "backgrounds"
    "dbus-1"
    "draw-on-gnome" # 空目录，扩展建了没用
    "fcitx5" # rime 的 build/ 和 userdb，见 MIGRATION.md 7.2
    "flatpak"
    "folks"
    "gegl-0.4"
    "gnome-settings-daemon"
    "gnome-shell"
    "gnome-software"
    "grilo-plugins"
    "gvfs-metadata"
    "icc"
    "icons"
    "keyrings" # C 类：秘密
    "neovide"
    "nvim" # lazy.nvim 插件，会自动重装
    "org.gnome.TextEditor"
    "recently-used.xbel"
    "sounds"
    "themes"
    "zoxide"
  ];

  # ============================================
  # 收进仓库时要剔掉的东西
  # ============================================
  # 清单里有几项是**整个目录**（.config/mozc、.config/fcitx5/conf），
  # 目录里混着日志、锁文件和缓存。照单全收的后果：
  #
  #   *.log            纯噪音，而且每次用输入法都在变，git 历史会被刷屏
  #   .server.lock     运行时锁
  #   .session.ipc     **记的是本机的套接字路径**，拷到新机器上是错的
  #   cached_layouts   fcitx5 的键盘布局缓存，会自己重建
  #
  # 在 push 那一步剔掉，而不是靠状态仓库的 .gitignore ——
  # gitignore 只是不提交，文件还是会躺在工作区里，restore 时又被铺回去。
  junkPatterns = [
    "*.log"
    ".server.lock"
    ".session.ipc"
    "cached_layouts"
  ];

  # VS Code 扩展：手工装的那几个。**不声明进 Nix 是有意的** ——
  # nixpkgs 里那几个版本比实际装的旧（claude-code 甚至退到 2.1.223，
  # 正是 Lesson-Learn/0010 记的那个被发布分支冻住的版本），
  # 而 CLI 那边已经用 manifest 覆写升上去了，装个旧扩展自相矛盾。
  # 所以归手工清单，由 migration-check 盯着别漏。
  vscodeExtensions = [
    "anthropic.claude-code"
    "brettm12345.nixfmt-vscode"
    "jnoortheen.nix-ide"
    "shd101wyy.markdown-preview-enhanced"
  ];

  # home-manager 的 dconf 模块会把值包成 gvariant
  # （{ _type = "gvariant"; type = "as"; value = [ ... ]; }，列表里每一项
  # 也各包一层），所以从 config.dconf.settings 读回来的**不是裸列表**。
  # 直接拿去 concatStringsSep 会报 "expected a list but found a set"，
  # 而且惰性求值让报错位置落在毫不相干的地方（实测指到了 fontconfig）。
  # 剥两层，用 `or` 兜底以防将来 home-manager 改成不包装。
  enabledExtensions =
    let
      v = config.dconf.settings."org/gnome/shell".enabled-extensions;
    in
    map (x: x.value or x) (v.value or v);

  # nix-flatpak 把 services.flatpak.packages 里的字符串规范化成了
  # { appId, bundle, commit, flatpakref, origin, sha256 } 这样的 attrset，
  # 同样不能直接当字符串列表用。
  flatpakApps = map (p: p.appId or p) osConfig.services.flatpak.packages;

  # ============================================
  # 清单一律落成文件，**不用 heredoc**
  # ============================================
  # 踩过：在 nix 缩进字符串里写 `cat <<'X' ... X`，终止符必须顶格，
  # 而 nix 的公共缩进剥离 + nixfmt 的重排会让它带上缩进，
  # bash 报 "syntax error: unexpected end of file"，指向的行号还离得很远。
  #
  # 用 writeText 把清单变成 store 里的文件，脚本只管 cat，
  # 缩进怎么变都不影响。顺带让清单在 store 里可直接查看。
  listFile = name: xs: pkgs.writeText name (lib.concatStringsSep "\n" xs + "\n");

  stateFilesList = listFile "state-files.txt" stateFiles;
  ignoredList = listFile "migration-ignored.txt" ignored;
  ignoredHomeList = listFile "migration-ignored-home.txt" ignoredHome;
  ignoredClaudeList = listFile "migration-ignored-claude.txt" ignoredClaude;
  vscodeList = listFile "vscode-extensions.txt" vscodeExtensions;
  extensionsList = listFile "gnome-extensions.txt" enabledExtensions;
  flatpakList = listFile "flatpak-apps.txt" flatpakApps;

  usageText = pkgs.writeText "state-sync-usage.txt" ''
    state-sync —— 搬运 Nix 管不到的用户状态（MIGRATION.md 的 B 类）

      state-sync status    看哪些路径有差异
      state-sync push      把 $HOME 里的状态收进仓库（不自动 commit）
      state-sync pull      git pull
      state-sync restore   把仓库里的状态铺回 $HOME

    仓库位置默认 ~/dotfiles-state，可用 STATE_REPO 覆盖。

    push 不自动提交。理由和 nixos-config 一样：人工看过再提交，
    不让一个刚改坏的配置覆盖掉好的。
  '';

  binPath = lib.makeBinPath [
    pkgs.coreutils
    pkgs.findutils
    pkgs.gnugrep
    pkgs.gnused
    pkgs.diffutils
    pkgs.git
  ];

  stateSync = pkgs.writeShellScriptBin "state-sync" ''
    # writeShellScriptBin 而非 writeShellApplication：后者构建期跑 shellcheck，
    # 而 shellcheck 在沙箱的 C locale 下打印不出中文，一有 warning 就崩在
    # commitBuffer: invalid argument 上（CLAUDE.md 记过）。
    set -uo pipefail
    export PATH=${binPath}:$PATH

    STATE_REPO="''${STATE_REPO:-$HOME/dotfiles-state}"
    files=$(cat ${stateFilesList})

    # 剔掉日志、锁文件、缓存。理由见 migration.nix 里 junkPatterns 那段。
    prune_junk() {
      find "$1" \( ${
        lib.concatMapStringsSep " -o " (p: "-name ${lib.escapeShellArg p}") junkPatterns
      } \) -delete 2>/dev/null || true
    }

    need_repo() {
      if [ ! -d "$STATE_REPO/.git" ]; then
        echo "找不到状态仓库：$STATE_REPO" >&2
        echo "先建一个：git init $STATE_REPO" >&2
        exit 1
      fi
    }

    cmd_status() {
      need_repo
      n=0
      while IFS= read -r rel; do
        [ -n "$rel" ] || continue
        src="$HOME/$rel"; dst="$STATE_REPO/$rel"
        if [ ! -e "$src" ] && [ ! -e "$dst" ]; then
          continue
        elif [ ! -e "$src" ]; then
          printf '  仅在仓库   %s\n' "$rel"; n=$((n+1))
        elif [ ! -e "$dst" ]; then
          printf '  仅在 HOME  %s\n' "$rel"; n=$((n+1))
        elif ! diff -rq "$src" "$dst" >/dev/null 2>&1; then
          printf '  有差异     %s\n' "$rel"; n=$((n+1))
        fi
      done <<< "$files"
      [ "$n" -eq 0 ] && echo "  一致。"
      echo
      echo "仓库 git 状态："
      git -C "$STATE_REPO" status -s | sed 's/^/  /' || true
    }

    cmd_push() {
      need_repo
      while IFS= read -r rel; do
        [ -n "$rel" ] || continue
        src="$HOME/$rel"; dst="$STATE_REPO/$rel"
        [ -e "$src" ] || continue
        mkdir -p "$(dirname "$dst")"
        rm -rf "$dst"
        cp -a "$src" "$dst"
        prune_junk "$dst"
        printf '  收入 %s\n' "$rel"
      done <<< "$files"
      echo
      echo "已收进 $STATE_REPO，**没有提交**。看过之后自己 commit："
      echo "  git -C $STATE_REPO add -A && git -C $STATE_REPO commit"
    }

    cmd_restore() {
      need_repo
      while IFS= read -r rel; do
        [ -n "$rel" ] || continue
        src="$STATE_REPO/$rel"; dst="$HOME/$rel"
        [ -e "$src" ] || continue
        mkdir -p "$(dirname "$dst")"
        rm -rf "$dst"
        cp -a "$src" "$dst"
        printf '  还原 %s\n' "$rel"
      done <<< "$files"
      echo
      echo "完成。输入法相关的还要做两件事，见 MIGRATION.md 第 7.2 节："
      echo "  rm -rf ~/.local/share/fcitx5/rime/build   # 里面固化着旧机器的 store 路径"
      echo "  让 Rime 自己重新生成 installation.yaml     # 里面的 UUID 是分机标识"
    }

    case "''${1:-}" in
      status)  cmd_status ;;
      push)    cmd_push ;;
      pull)    need_repo; git -C "$STATE_REPO" pull ;;
      restore) cmd_restore ;;
      *)       cat ${usageText} ;;
    esac
  '';

  migrationCheck = pkgs.writeShellScriptBin "migration-check" ''
    set -uo pipefail
    export PATH=${binPath}:${
      lib.makeBinPath [
        pkgs.flatpak
        pkgs.glib
      ]
    }:$PATH

    STATE_REPO="''${STATE_REPO:-$HOME/dotfiles-state}"

    findings=0
    note() { printf '  %s\n' "$1"; findings=$((findings + 1)); }

    printf '\nFlatpak\n'
    declared=$(cat ${flatpakList})
    if command -v flatpak >/dev/null 2>&1; then
      while IFS= read -r app; do
        [ -n "$app" ] || continue
        grep -qxF "$app" <<< "$declared" \
          || note "装了但 modules/flatpak.nix 里没声明：$app"
      done < <(flatpak list --app --columns=application 2>/dev/null || true)
    else
      note "flatpak 命令不可用，跳过这一项"
    fi

    printf '\nGNOME 扩展\n'
    hm_enabled=$(cat ${extensionsList})
    if command -v gnome-extensions >/dev/null 2>&1; then
      while IFS= read -r uuid; do
        [ -n "$uuid" ] || continue
        grep -qxF "$uuid" <<< "$hm_enabled" \
          || note "已启用但 home/toru.nix 的 enabled-extensions 里没有：$uuid"
      done < <(gnome-extensions list --enabled 2>/dev/null || true)

      # 反向：声明了但机器上根本没装。GNOME 对不认识的 UUID **静默忽略**，
      # 所以这种垃圾平时完全看不出来 —— 实测就有一个
      # gnome-shell-screenshot@ttll.de 这样躺在 dconf 里。
      while IFS= read -r uuid; do
        [ -n "$uuid" ] || continue
        gnome-extensions info "$uuid" >/dev/null 2>&1 \
          || note "声明了但没装（死 UUID，GNOME 静默忽略）：$uuid"
      done <<< "$hm_enabled"
    else
      note "gnome-extensions 命令不可用，跳过这一项"
    fi

    printf '\nVS Code 扩展（手工清单）\n'
    known=$(cat ${vscodeList})
    if [ -d "$HOME/.vscode/extensions" ]; then
      for d in "$HOME/.vscode/extensions"/*/; do
        [ -d "$d" ] || continue
        b=$(basename "$d")
        # 目录名是 <publisher>.<name>-<版本>，去掉版本后缀
        id=$(sed 's/-[0-9][0-9.]*\(-[a-z0-9]*\)*$//' <<< "$b")
        [ "$id" = "stylix.stylix" ] && continue
        grep -qxF "$id" <<< "$known" \
          || note "装了但不在 home/migration.nix 的 vscodeExtensions 清单里：$id"
      done
      while IFS= read -r id; do
        [ -n "$id" ] || continue
        ls -d "$HOME/.vscode/extensions/$id"* >/dev/null 2>&1 \
          || note "清单里有但没装：$id"
      done <<< "$known"
    else
      note "~/.vscode/extensions 不存在，跳过这一项"
    fi

    # home-manager 接管一个已存在的普通文件时，会把原文件改名成
    # <原名>.hm-bak 再继续（hosts/<主机>/default.nix 的 backupFileExtension）。
    # 那是**接管成功的证据**，不是漂移 —— 但核对完就该删，不然会一直躺着，
    # 而且会让上面那条「目录里每个文件都是 store 链接」的判定失败，
    # 把整个目录误报成「没人认领」。实测就是这么发现 ~/.config/git 的。
    #
    # 单列一节而不是塞进白名单：塞白名单等于永远看不见它们。
    printf '\nhome-manager 的接管备份\n'
    while IFS= read -r bak; do
      [ -n "$bak" ] || continue
      orig=''${bak%.hm-bak}
      if [ -e "$orig" ] && diff -q "$orig" "$bak" >/dev/null 2>&1; then
        note "和现役内容一致，可以删：''${bak#"$HOME"/} "
      else
        note "**和现役内容不一致，先核对再删**：''${bak#"$HOME"/}"
      fi
    done < <(find "$HOME" -maxdepth 5 -name '*.hm-bak' 2>/dev/null)

    printf '\nB 类状态（dotfiles-state）\n'
    files=$(cat ${stateFilesList})
    if [ -d "$STATE_REPO/.git" ]; then
      while IFS= read -r rel; do
        [ -n "$rel" ] || continue
        [ -e "$HOME/$rel" ] || continue
        [ -e "$STATE_REPO/$rel" ] || note "在 HOME 里但还没 state-sync push：$rel"
      done <<< "$files"
    else
      note "状态仓库还没建：$STATE_REPO（见 MIGRATION.md 第 7.1 节）"
    fi

    # ============================================
    # 判定「这东西有没有人管」
    # ============================================
    #   单个文件 -> 本身就是解析后落在 /nix/store 里的符号链接
    #   一个目录 -> 目录**非空**，且里面每一个文件都是这样的符号链接
    #
    # 为什么目录要逐个文件看：home-manager 不会把整个目录软链过去，
    # 它是**逐个文件**链的。只查顶层符号链接会把 ~/.config/bat、btop、
    # ghostty、tmux 一大批全部误报（实测 14 个误报）。
    #
    # 为什么必须用 readlink -f 而不是 find -lname：
    # `-lname` 匹配的是**链接里存的原始字符串**，不跟着解析。
    # 而 ~/.agents/skills/<名> 指向的是 ~/.local/share/agent-skills/<名>，
    # 那个才是指向 store 的链接 —— 两跳。用 -lname 的话这些
    # skills sync 管得好好的目录会被报成「没人认领」。
    #
    # 空目录不算「已认领」—— 那通常是某个程序建了就没用的残留。
    is_managed() {
      p="$1"
      if [ -L "$p" ]; then
        case "$(readlink -f "$p")" in /nix/store/*) return 0 ;; esac
        return 1
      fi
      [ -d "$p" ] || return 1
      total=0
      linked=0
      while IFS= read -r f; do
        total=$((total + 1))
        if [ -L "$f" ]; then
          case "$(readlink -f "$f")" in /nix/store/*) linked=$((linked + 1)) ;; esac
        fi
      done < <(find "$p" \( -type f -o -type l \) 2>/dev/null)
      [ "$total" -gt 0 ] && [ "$total" -eq "$linked" ]
    }

    scan_dir() {
      base="$1"
      ign="$2"
      [ -d "$base" ] || return 0
      for p in "$base"/*; do
        [ -e "$p" ] || continue
        b=$(basename "$p")
        # $HOME 根下的一堆随手记的 *.txt 笔记，不是配置
        case "$b" in *.txt) continue ;; esac
        is_managed "$p" && continue
        grep -qxF "$b" <<< "$ign" && continue
        rel=''${p#"$HOME"/}
        grep -qxF "$rel" <<< "$files" && continue
        grep -q "^$rel/" <<< "$files" && continue
        note "没人认领：~/$rel"
      done
    }

    # $HOME 根下。**这一层原先没扫**，~/.claude 这类开发工具的配置全在盲区。
    # 用 shopt -s dotglob 让 * 也匹配点开头的条目。
    printf '\n~/ 根下没人认领的\n'
    shopt -s dotglob
    scan_dir "$HOME" "$(cat ${ignoredHomeList})"
    shopt -u dotglob

    printf '\n~/.config 和 ~/.local/share 里没人认领的\n'
    ign_xdg=$(cat ${ignoredList})
    scan_dir "$HOME/.config" "$ign_xdg"
    scan_dir "$HOME/.local/share" "$ign_xdg"

    # ~/.claude 单独扫。整个目录加白名单的话，以后 Claude Code 在这里
    # 新增一个该管的配置文件就发现不了了 —— 而那正是这工具要防的事。
    printf '\n~/.claude 里没人认领的\n'
    scan_dir "$HOME/.claude" "$(cat ${ignoredClaudeList})"

    echo
    if [ "$findings" -eq 0 ]; then
      echo "没有发现漂移。"
    else
      echo "共 $findings 处需要处理。"
      echo
      echo "每一处问自己：能进 Nix 吗（A）？可版本化吗（B）？是秘密吗（C）？"
      echo "判据见 MIGRATION.md 第 0 节，加完记得同步那份文档第 10 节的表。"
    fi
  '';

  # ============================================
  # 构建期回归测试
  # ============================================
  # 照 home/skills-tests.sh 的先例：测试不过就 build 不出来。
  #
  # 守的是 state-sync —— push 会把 $HOME 的东西复制进一个将来要推上
  # GitHub 的仓库（收多了就是泄密），restore 会 rm -rf 后覆盖 $HOME
  # 里的文件（写错不可逆）。migration-check 是只读的，误报顶多浪费几分钟，
  # 不值得同等力度的测试。**测试力度按后果分配。**
  migrationTests = pkgs.runCommand "migration-tests" { } ''
    export PATH=${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.git
        pkgs.diffutils
        pkgs.gnugrep
        pkgs.gnused
      ]
    }:$PATH
    export STATE_SYNC_BIN=${stateSync}/bin/state-sync
    bash ${./migration-tests.sh}
    touch $out
  '';

  # 把测试挂进依赖链：测试不过，这个包就产不出来，nrb 停在这一步。
  gated = pkgs.runCommand "migration-tools" { } ''
    test -e ${migrationTests}
    mkdir -p $out/bin
    ln -s ${stateSync}/bin/state-sync           $out/bin/state-sync
    ln -s ${migrationCheck}/bin/migration-check $out/bin/migration-check
  '';
in
{
  options.custom.migration.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "安装 state-sync 与 migration-check。";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ gated ];
  };
}
