# claude-code 和 grok-build 不跟着 nix flake update 走：
# nixos-26.05 把它们冻在旧版，版本钉在 modules/ 下的两个 JSON 里。
# 这条命令把「拉官方版本、改 JSON、用户态构建本机两层」收成一次。
# 不 switch，不 commit。不要改用 claude update / grok update，
# 那两个会把二进制装进家目录，脱离 Nix。
{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}:

let
  nixosHost = osConfig.custom.flakeHost;
  system = pkgs.stdenv.hostPlatform.system;
  platform =
    {
      x86_64-linux = "linux-x86_64";
      aarch64-linux = "linux-aarch64";
    }
    .${system};
  toolPath = lib.makeBinPath (
    with pkgs;
    [
      coreutils
      curl
      gnugrep
      jq
    ]
  );

  agentsUpdate = pkgs.writeShellScriptBin "agents-update" ''
    set -euo pipefail
    export PATH="${toolPath}:$PATH"

    REPO="''${NIXOS_CONFIG_DIR:-${config.home.homeDirectory}/nixos-config}"
    USER_NAME="${config.home.username}"
    HOST="${nixosHost}"
    SYSTEM="${system}"
    PLATFORM="${platform}"

    usage() {
      printf '%s\n' \
        "用法: agents-update [claude|grok] [版本]" \
        "  不带参数    两个都跟官方最新（claude 的 latest，grok 的 stable）" \
        "  claude      只更新 claude-code。也可写 claude-code" \
        "  grok        只更新 grok-build。也可写 grok-build" \
        "  版本        不跟最新，钉死这个号，例如 agents-update claude 2.1.284" \
        "" \
        "只改 modules/ 下的 JSON，再用户态构建本机（$HOST）的两层。" \
        "不 switch，不 commit。claude 取的是 manifest.json，不是 manifest.zst.json。"
    }

    die() {
      printf 'agents-update: %s\n' "$1" >&2
      exit 1
    }

    is_version() {
      printf '%s' "$1" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'
    }

    changed=0

    update_claude() {
      local want="$1" old new tmp got
      old=$(jq -r .version "$REPO/modules/claude-code-manifest.json")
      if [ -n "$want" ]; then
        new=$want
      else
        new=$(curl -fsSL https://downloads.claude.ai/claude-code-releases/latest)
        new=$(printf '%s' "$new" | tr -d '[:space:]')
      fi
      is_version "$new" || die "claude 版本号不像版本：$new"
      if [ "$new" = "$old" ]; then
        printf '  %-12s 无变化 (%s)\n' claude-code "$old"
        return
      fi
      tmp=$(mktemp)
      # 26.05 的包定义只认这份。同目录的 manifest.zst.json 是另一套格式。
      curl -fsSL "https://downloads.claude.ai/claude-code-releases/$new/manifest.json" -o "$tmp"
      got=$(jq -r .version "$tmp")
      [ "$got" = "$new" ] || die "manifest 里的版本是 $got，要的是 $new"
      jq -e '.platforms["linux-x64"].checksum | type == "string" and length > 0' "$tmp" >/dev/null \
        || die "manifest 里没有 linux-x64 的 checksum"
      mv "$tmp" "$REPO/modules/claude-code-manifest.json"
      printf '  %-12s %s -> %s\n' claude-code "$old" "$new"
      changed=1
    }

    update_grok() {
      local want="$1" old new tmp hash url
      old=$(jq -r .version "$REPO/modules/grok-build-version.json")
      if [ -n "$want" ]; then
        new=$want
      else
        new=$(curl -fsSL https://x.ai/cli/stable)
        new=$(printf '%s' "$new" | tr -d '[:space:]')
      fi
      is_version "$new" || die "grok 版本号不像版本：$new"
      if [ "$new" = "$old" ]; then
        printf '  %-12s 无变化 (%s)\n' grok-build "$old"
        return
      fi
      url="https://x.ai/cli/grok-$new-$PLATFORM"
      printf 'agents-update: 下载 %s 以计算哈希\n' "$url"
      hash=$(nix hash convert --hash-algo sha256 "$(nix-prefetch-url "$url")")
      tmp=$(mktemp)
      jq --arg v "$new" --arg h "$hash" --arg sys "$SYSTEM" \
        '.version = $v | .hashes[$sys] = $h' \
        "$REPO/modules/grok-build-version.json" >"$tmp"
      mv "$tmp" "$REPO/modules/grok-build-version.json"
      printf '  %-12s %s -> %s\n' grok-build "$old" "$new"
      changed=1
    }

    cd "$REPO" || die "进不了仓库 $REPO"

    target="''${1:-all}"
    pin="''${2:-}"
    case "$target" in
      -h | --help | help)
        usage
        exit 0
        ;;
      all)
        [ -z "$pin" ] || die "一次更新两个时不能带版本号。分开跑：agents-update claude <版本>"
        printf 'agents-update: 查询 claude-code 与 grok-build\n'
        update_claude ""
        update_grok ""
        ;;
      claude | claude-code)
        printf 'agents-update: 查询 claude-code\n'
        update_claude "$pin"
        ;;
      grok | grok-build)
        printf 'agents-update: 查询 grok-build\n'
        update_grok "$pin"
        ;;
      *)
        die "未知目标：$target（agents-update --help）"
        ;;
    esac

    if [ "$changed" = 0 ]; then
      printf 'agents-update: 已是要的版本，不用重建。\n'
      exit 0
    fi

    printf '\nagents-update: 用户态构建系统层（%s）…\n' "$HOST"
    nix build "$REPO#nixosConfigurations.$HOST.config.system.build.toplevel" \
      --out-link /tmp/res
    printf 'agents-update: 用户态构建 home 层…\n'
    nix build "$REPO#nixosConfigurations.$HOST.config.home-manager.users.$USER_NAME.home.activationPackage" \
      --out-link /tmp/hm

    check_single() {
      local label=$1 n
      n=$(nix path-info -r /tmp/res /tmp/hm | grep -F "$label" | sort -u | wc -l)
      n=$(printf '%s' "$n" | tr -d '[:space:]')
      if [ "$n" != 1 ]; then
        printf 'agents-update: 闭包里 %s 有 %s 个派生，先别 switch\n' "$label" "$n" >&2
        nix path-info -r /tmp/res /tmp/hm | grep -F "$label" | sort -u >&2 || true
        exit 1
      fi
      nix path-info -r /tmp/res /tmp/hm | grep -F "$label" | sort -u
    }
    printf '\n'
    check_single claude-code-
    check_single grok-build-

    printf '\nagents-update: JSON 已更新，两层都构建通过，闭包里各只有一个派生。\n'
    printf '接下来由你决定：\n\n'
    printf '  cd %s\n' "$REPO"
    printf '  git diff modules/claude-code-manifest.json modules/grok-build-version.json\n'
    printf '  sudo nixos-rebuild switch --flake %s#%s\n\n' "$REPO" "$HOST"
    printf 'switch 之后看 claude --version 和 grok --version。\n'
    printf '不替你 switch，也不替你 commit。\n'
  '';
in
{
  home.packages = [ agentsUpdate ];
}
