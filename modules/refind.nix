{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  cfg = config.custom.refind;

  # ============================================
  # 为什么 rEFInd 不走 boot.loader
  # ============================================
  # nixos-26.05 里确实有官方的 boot.loader.refind 模块，但这里**故意不用**：
  #
  #   1. 它设 system.boot.loader.id = "refind"，源码注释写明
  #      "so only one of them can be set at once" —— 和 systemd-boot 互斥。
  #      而这套方案要的正是两层：rEFInd 做顶层入口，systemd-boot 继续管
  #      generation（回滚安全网在那一层，不能丢）。
  #   2. 它把**每个 generation 展开成一条顶层 menuentry**，菜单里排一长串
  #      NixOS 图标，正好毁掉选 rEFInd 的理由。
  #   3. 它每次 rebuild 整个重写 refind.conf。
  #
  # 所以 rEFInd 在这里是：Nix 声明式地把素材备好（二进制、生成好的主题、
  # refind.conf），再由 refind-sync 这条**手动跑**的命令写进 ESP。
  # nixos-rebuild 因此永远不会意外改动引导分区 —— 引导坏掉等于开不了机，
  # 这是全仓库风险最高的一处，值得用「只在主动触发时才动」换取安全。
  #
  # 完整迁移步骤见 MIGRATION.md 第 6 节。

  fontDir = "${pkgs.nerd-fonts.jetbrains-mono}/share/fonts/truetype/NerdFonts/JetBrainsMono";

  # ============================================
  # rEFInd 在 ESP 上的安装目录 —— 只定义一次
  # ============================================
  # refind-sync 往这里写，refind.conf 里的 icon 路径也要引用它。
  # 两处各写一份的话，改了一处忘另一处，症状是图标变成占位图而**不报错**。
  #
  # **注意 rEFInd 自己的路径基准是不一致的**，这是真踩过的坑：
  #
  #   banner      （theme.conf）  相对 rEFInd 目录
  #   icons_dir   （theme.conf）  相对 rEFInd 目录
  #   icon        （menuentry 内）**相对 ESP 卷根**   <-- 不一样！
  #
  # 上游 refind.conf-sample 里 6 处 icon 示例全是 /EFI/refind/icons/... 这种
  # 从卷根算起的绝对路径。按 banner 的规则写成相对 rEFInd 目录的话，
  # rEFInd 不会报任何错，只是静默显示一个约 32x32 的内置「加载失败」方块 ——
  # 而同目录下经 icons_dir 加载的功能图标一切正常，极具迷惑性。
  refindDir = "/EFI/refind";
  themeDir = "${refindDir}/themes/finn-term";

  # 硬件那几行由 refind-hwinfo 探测、写进 hosts/<主机>/hwinfo.nix、提交进版本库。
  # 内核版本**不走那条路** —— 它跟着 nixpkgs 滚，写死进生成文件必然过期。
  # 这里直接从求值中的配置取，永远和实际要启动的内核一致。
  allRows =
    cfg.bootRows
    ++ lib.optional cfg.appendKernelRow {
      name = "kernel ";
      value = "LINUX ${config.boot.kernelPackages.kernel.version} ";
      status = "[ LOADED ]";
    };

  # ============================================
  # 主题生成：为什么用包装脚本而不是 substituteInPlace
  # ============================================
  # 上游 gen.py 的配置是文件顶部一个硬编码块（W/H、HOSTNAME、BOOT_ROWS、
  # 两个字体路径），既没有命令行参数也没有环境变量。
  #
  # 直觉做法是 substituteInPlace 改那个块，但 BOOT_ROWS 是**多行列表** ——
  # 多行 --replace-fail 写在 nix 缩进字符串里会被 nixfmt 重排缩进，
  # 缩进一变就匹配不上，构建失败且报错完全看不出原因。
  # 这个坑 CLAUDE.md 在 rime-frost 的 lua 补丁那里已经记过一次。
  #
  # 改成 import gen 之后覆盖模块全局变量：gen.py 里的函数体是在**调用时**
  # 查全局的（不是定义时捕获），所以覆盖完再调就够了，上游源码一个字不用动。
  #
  # 额外好处：上游改排版、改注释、改配色都影响不到我们；
  # 而上游要是把这些变量改名，构建会当场 AttributeError 失败 ——
  # 响亮地坏掉，比静默地拿默认值生成一张别人的壁纸好。
  genWrapper = pkgs.writeText "finn-term-gen.py" ''
    import os, sys

    sys.path.insert(0, os.path.join(os.getcwd(), "src"))
    import gen

    gen.OUT = os.environ["out"]
    gen.W, gen.H = ${toString cfg.resolution.width}, ${toString cfg.resolution.height}
    gen.HOSTNAME = ${builtins.toJSON cfg.hostname}
    gen.FONT_PATH = ${builtins.toJSON "${fontDir}/JetBrainsMonoNerdFont-Regular.ttf"}
    gen.FONT_BOLD = ${builtins.toJSON "${fontDir}/JetBrainsMonoNerdFont-Bold.ttf"}

    # BOOT_ROWS 经 builtins.toJSON 落地成 JSON 数组，而 JSON 数组同时就是
    # 合法的 Python 字面量，省掉手工拼引号转义。gen.py 那边写的是
    # `for name, val, status in BOOT_ROWS`，解包对 list 和 tuple 都成立。
    gen.BOOT_ROWS = ${
      builtins.toJSON (
        map (r: [
          r.name
          r.value
          r.status
        ]) allRows
      )
    }

    os.makedirs(os.path.join(gen.OUT, "fonts"), exist_ok=True)
    gen.make_background()
    gen.make_selection(288, 10, "selection_big.png", lw=4)
    gen.make_selection(128, 6, "selection_small.png", lw=3)
    gen.make_font(30)
  '';

  theme = pkgs.stdenvNoCC.mkDerivation {
    pname = "refind-theme-finn-term";
    version = inputs.refind-finn-term.shortRev or "unknown";

    src = inputs.refind-finn-term;

    nativeBuildInputs = [ (pkgs.python3.withPackages (ps: [ ps.pillow ])) ];

    dontConfigure = true;

    buildPhase = ''
      runHook preBuild
      mkdir -p $out/fonts
      python3 ${genWrapper}
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      # 图标是现成的 PNG，原样拿来（135 个，含 os_nixos 和 os_win）
      cp -r icons $out/icons

      # theme.conf 里的 resolution 必须和生成背景图时用的一致，
      # 否则 rEFInd 会按另一个尺寸渲染，背景被拉伸或平铺。
      # 用单行 --replace-fail：上游哪天改了这一行，构建会当场失败，
      # 而不是悄悄留下一个对不上的分辨率。
      substitute theme.conf $out/theme.conf \
        --replace-fail 'resolution 2560 1440' \
                       'resolution ${toString cfg.resolution.width} ${toString cfg.resolution.height}'

      runHook postInstall
    '';

    meta = {
      description = "finn-term rEFInd 主题，按本机分辨率与主机名生成";
      homepage = "https://github.com/FaeArtz/refind-finn-term";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
    };
  };

  refindConf = pkgs.writeText "refind.conf" ''
    # 本文件由 modules/refind.nix 生成。
    # **不要直接编辑 ESP 里的这一份** —— 下次 refind-sync 会整个覆盖它。
    # 要改就改 hosts/<主机>/default.nix 里的 custom.refind.*。

    include themes/finn-term/theme.conf

    timeout ${toString cfg.timeout}
    resolution ${toString cfg.resolution.width} ${toString cfg.resolution.height}

    # 启动项 = 下面手写的 menuentry + 外接介质/光驱的自动扫描。
    #
    # 刻意**不扫内置盘**：NixOS 会往 ESP 的 EFI/nixos/ 里散一堆内核 .efi，
    # 自动扫描会把它们每一个都变成一条菜单项，菜单瞬间变成垃圾场。
    # 手写 menuentry 则是每台机器一模一样、完全可预测的。
    #
    # 保留 external 和 optical，是为了插上 U 盘救援介质时**不用改配置**
    # 就能直接启动 —— 真出事的时候没人想先去编辑 refind.conf。
    scanfor manual,external,optical

    menuentry "NixOS" {
        icon   ${themeDir}/icons/os_nixos.png
        loader /EFI/systemd/systemd-bootx64.efi
    }
    ${cfg.extraEntries}
  '';

  # ============================================
  # refind-hwinfo：探测硬件，写出 hosts/<主机>/hwinfo.nix
  # ============================================
  # 为什么需要它：那张启动画面是 Nix 在**构建时**生成的，而 Nix 构建跑在
  # 沙箱里，读不到宿主机的 PCI 设备和 sysfs。所以「抓取硬件」这件事只能
  # 发生在构建之外。
  #
  # 选的是 nixos-generate-config 的路子：**工具生成一个纯文本 nix 文件，
  # 提交进版本库，构建时当普通配置读**。这样成品仍然是声明式的、被
  # flake.lock 钉死的、两台机器上可复现的 —— 而不是每次 refind-sync
  # 现场探测、同一份配置在不同机器上出不同结果。
  #
  # 附带的好处：探测判断错了（比如把某张卡认成核显）不用回来调脚本，
  # 直接改 hwinfo.nix 就行。它不在开机路径上，错了只是画面上一行字不对。
  #
  # 完整流程（少一步都不行）：
  #     refind-hwinfo          写出 hwinfo.nix
  #     git add hosts/<主机>/hwinfo.nix     新文件，flake 看不见未跟踪文件
  #     nrb                    Nix 读它 -> 跑 gen.py -> 新 PNG 进 store
  #     sudo refind-sync       把新 store 路径拷进 ESP
  #
  # 中间那次 nrb 不能省：refind-sync 里的主题路径是**构建时烤死的 store
  # 路径**，不重新构建的话新 PNG 根本不存在，sync 拷的还是旧那份。
  refindHwinfo = pkgs.writeShellScriptBin "refind-hwinfo" ''
    set -euo pipefail

    export PATH=${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.util-linux
        pkgs.pciutils
        pkgs.gnused
        pkgs.gawk
        pkgs.gnugrep
        pkgs.dmidecode
      ]
    }:$PATH

    # 默认路径用的是 flakeHost 而不是 $(hostname)：
    # 这两个在本仓库里是不一样的（hosts/thinkpad/ vs thinkpad-nixos）。
    out=''${1:-hosts/${cfg.flakeHost}/hwinfo.nix}

    if [ ! -e flake.nix ]; then
      echo "请在仓库根目录跑这个命令（当前目录下找不到 flake.nix）。" >&2
      exit 1
    fi

    norm() { tr 'a-z' 'A-Z' | sed 's/([RT]M*)//g; s/(R)//g; s/(TM)//g; s/  */ /g; s/^ //; s/ $//'; }

    # ---------- CPU ----------
    cpu=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- \
          | sed 's/ CPU @.*//; s/ @ .*//; s/ Processor//' | norm)

    # ---------- GPU ----------
    # 核显与独显分开收集。判据：PCI 地址在 bus 0000:00 上的算核显；
    # 否则看有没有显存节点（amdgpu 的 mem_info_vram_total / Intel Arc 的
    # lmem_total_bytes），有才算独显。
    #
    # **这个判据只在单核显机器上实测过**（写它的时候手头只有这一台）。
    # AMD 的 APU 不在 bus 00 上且也报显存，有可能被误判成独显。
    # 真遇到了直接改生成出来的 hwinfo.nix，比改这里省事。
    igpu=()
    dgpu=()
    for card in /sys/class/drm/card[0-9]; do
      [ -e "$card/device/uevent" ] || continue
      addr=$(basename "$(readlink -f "$card/device")")
      line=$(lspci -mm -s "''${addr#0000:}" 2>/dev/null) || continue
      ven=$(printf '%s' "$line" | awk -F'"' '{print $4}')
      raw=$(printf '%s' "$line" | awk -F'"' '{print $6}')
      # "Skylake-U GT2 [HD Graphics 520]" -> "HD Graphics 520"
      case "$raw" in
        *\[*\]*) name=''${raw##*[}; name=''${name%]} ;;
        *)       name=$raw ;;
      esac
      vram=""
      for f in "$card/device/mem_info_vram_total" "$card/lmem_total_bytes"; do
        [ -r "$f" ] && { vram="$(( $(cat "$f") / 1048576 ))M"; break; }
      done
      desc=$(printf '%s %s' "''${ven%% *}" "$name" | norm)
      if [ -n "$vram" ]; then desc="$desc / $vram"; else desc="$desc / SHARED"; fi
      case "$addr" in
        0000:00:*) igpu+=("$desc") ;;
        *)         if [ -n "$vram" ]; then dgpu+=("$desc"); else igpu+=("$desc"); fi ;;
      esac
    done

    # ---------- 内存 ----------
    kb=$(awk '/MemTotal/{print $2}' /proc/meminfo)
    g=$(( (kb + 1048575) / 1048576 ))
    p=1; while [ "$p" -lt "$g" ]; do p=$((p*2)); done
    mem="$((p*1024))M"
    # 内存代数（DDR3/DDR4/…）只有 dmidecode 拿得到，而它要 root。
    # 没有就省略 —— 缺一个代数比要求整条命令 sudo 划算。
    mtype=$(dmidecode -t memory 2>/dev/null \
            | awk -F': ' '/^\tType:/ && $2 !~ /Unknown|Other/ {print $2; exit}' || true)
    [ -n "$mtype" ] && mem="$mem $mtype"

    # ---------- 磁盘 ----------
    rootsrc=$(findmnt -no SOURCE / | sed 's/\[.*//')
    rd=$(lsblk -no PKNAME "$rootsrc" 2>/dev/null | head -1)
    [ -n "$rd" ] || rd=$(basename "$rootsrc")
    # 型号尾部的批次号（-00BTW 之类）对人没有信息量，去掉
    dm=$(lsblk -dno MODEL "/dev/$rd" 2>/dev/null | sed 's/-[0-9A-Z]\{4,6\}$//; s/  *$//' | norm)
    by=$(lsblk -dnbo SIZE "/dev/$rd" 2>/dev/null | head -1)
    if [ "$by" -ge 1000000000000 ]; then
      ds="$(( (by + 500000000000) / 1000000000000 ))TB"
    else
      ds="$(( (by + 500000000) / 1000000000 ))GB"
    fi

    # ---------- 写文件 ----------
    row() { printf '    {\n      name = "%s";\n      value = "%s ";\n      status = "%s";\n    }\n' "$1" "$2" "$3"; }

    mkdir -p "$(dirname "$out")"
    {
      echo '# 本文件由 refind-hwinfo 生成。'
      echo '#'
      echo '# 重新生成：在仓库根目录跑 refind-hwinfo，然后 nrb，再 sudo refind-sync。'
      echo '# 换了硬件就重跑一次。探测判断错了可以直接改这个文件 ——'
      echo '# 它不在开机路径上，错了只是启动画面上一行字不对。'
      echo '#'
      echo '# 内核版本不在这里：它跟着 nixpkgs 滚，由 modules/refind.nix 在'
      echo '# 求值时从 config.boot.kernelPackages 取，永远不会过期。'
      echo '{'
      echo '  custom.refind.bootRows = ['
      row "cpu    " "$cpu" "[ ONLINE ]"
      if [ $(( ''${#igpu[@]} + ''${#dgpu[@]} )) -le 1 ]; then
        for x in ''${igpu[@]+"''${igpu[@]}"} ''${dgpu[@]+"''${dgpu[@]}"}; do
          row "gpu    " "$x" "[ ONLINE ]"
        done
      else
        for x in ''${igpu[@]+"''${igpu[@]}"}; do row "igpu   " "$x" "[ ONLINE ]"; done
        for x in ''${dgpu[@]+"''${dgpu[@]}"}; do row "dgpu   " "$x" "[ ONLINE ]"; done
      fi
      row "memory " "$mem" "[ OK ]"
      row "disk   " "$dm $ds" "[ MOUNTED ]"
      echo '  ];'
      echo '}'
    } > "$out"

    echo "已写出 $out"
    echo
    cat "$out"
    echo
    echo "接下来（三步都要，少一步图片不会更新）："
    echo "  git add $out            # 新文件，flake 看不见未跟踪文件"
    echo "  sudo nixos-rebuild switch --flake .#${cfg.flakeHost}"
    echo "  sudo refind-sync"
    if [ "$(id -u)" -ne 0 ]; then
      echo
      echo "提示：内存代数（DDR3/DDR4）要 root 才读得到。"
      echo "      想要的话用 sudo refind-hwinfo 重跑一次。"
    fi
  '';

  refindSync = pkgs.writeShellScriptBin "refind-sync" ''
    # 注意：用 writeShellScriptBin 而不是 writeShellApplication。
    # 后者会在构建时跑 shellcheck，而 shellcheck 在沙箱的 C locale 下
    # 打印不出中文，一有 warning 就崩在 commitBuffer: invalid argument 上，
    # 报错完全看不出原因（CLAUDE.md 记过，agent-skills 的脚本同理）。
    set -euo pipefail

    # writeShellScriptBin 不设 PATH，脚本会继承调用者的环境。
    # sudo 下的 PATH 取决于 secure_path，不能假定 findmnt / mountpoint 在里面。
    export PATH=${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.util-linux
        pkgs.gnused
      ]
    }:$PATH

    if [ "$(id -u)" -ne 0 ]; then
      echo "refind-sync 要写 ESP 和 NVRAM，必须 root。" >&2
      echo "请用：sudo refind-sync" >&2
      exit 1
    fi

    efibootmgr=${pkgs.efibootmgr}/bin/efibootmgr

    sync_esp() {
      esp="$1"

      if ! mountpoint -q "$esp"; then
        echo "错误：$esp 不是挂载点，跳过。" >&2
        return 1
      fi

      dest="$esp${refindDir}"
      echo "==> 写入 $dest"

      # ============================================
      # 这里**不能**用 install -m，也不能让 cp 保留模式
      # ============================================
      # ESP 是 vfat，挂载参数是 fmask=0077,dmask=0077，权限位由挂载强制，
      # 文件一律是 0700。内核的 vfat 驱动在 chmod 请求的模式和挂载参数
      # 算出来的模式不一致时直接返回 EPERM。
      #
      # 于是 `install -Dm0644` 会在 chmod 那一步失败，配合 set -e
      # 整个脚本停在第一个文件上；`cp` 不加 --no-preserve=mode 也一样，
      # 因为 store 里的源文件是 0444，它会试图把这个模式套过去。
      #
      # 用 --no-preserve=mode 让 cp 根本不发 chmod，权限交给挂载参数决定。
      mkdir -p "$dest"
      cp --no-preserve=mode ${pkgs.refind}/share/refind/refind_x64.efi "$dest/refind_x64.efi"
      cp --no-preserve=mode ${refindConf} "$dest/refind.conf"

      # 主题整个重铺而不是增量覆盖：换主题或改分辨率之后，
      # 旧的 background.png 留在那里会被 theme.conf 继续引用。
      rm -rf "$esp${themeDir}"
      mkdir -p "$esp${themeDir}"
      cp -r --no-preserve=mode ${theme}/. "$esp${themeDir}/"
    }

    register_nvram() {
      esp="$1"

      dev=$(findmnt -no SOURCE "$esp")
      name=$(basename "$dev")
      part=$(cat "/sys/class/block/$name/partition")
      disk="/dev/$(basename "$(readlink -f "/sys/class/block/$name/..")")"

      echo "==> NVRAM: disk=$disk part=$part"

      # 先删掉已有的 rEFInd 项。不删的话每跑一次就多一条，
      # 启动菜单里会堆出一排一模一样的 rEFInd。
      #
      # cut -f1 那一段不能省。efibootmgr 的输出是
      #     Boot0003* Linux Boot Manager<TAB>HD(1,GPT,...)/\EFI\systemd\...
      # 标签后面还跟着制表符和设备路径，所以直接拿 `rEFInd$` 去匹配
      # 永远匹配不上，旧项删不掉，每跑一次就多一条重复的 NVRAM 项。
      # 先用 cut 按制表符截掉设备路径，再匹配行尾就准确了。
      "$efibootmgr" | cut -f1 \
        | sed -n 's/^Boot\([0-9A-Fa-f]\{4\}\)\*\{0,1\} rEFInd$/\1/p' \
        | while read -r num; do
            echo "    删除已有项 Boot$num"
            "$efibootmgr" --quiet --delete-bootnum --bootnum "$num"
          done

      # --create 会把新项插到 BootOrder 最前面，所以这一条同时完成
      # 「建项」和「提到第一顺位」两件事。
      "$efibootmgr" --quiet --create \
        --disk "$disk" --part "$part" \
        --loader '\EFI\refind\refind_x64.efi' \
        --label 'rEFInd'
    }

    for esp in ${lib.concatStringsSep " " (map lib.escapeShellArg cfg.espMountPoints)}; do
      sync_esp "$esp"
    done

    ${lib.optionalString cfg.registerNvram ''
      register_nvram ${lib.escapeShellArg (builtins.head cfg.espMountPoints)}
    ''}

    echo
    echo "完成。当前 UEFI 启动顺序："
    "$efibootmgr" | grep -E '^(BootOrder|Boot[0-9A-Fa-f]{4})' || true
    echo
    echo "安全网：上面那条 'Linux Boot Manager' 是 systemd-boot。"
    echo "rEFInd 出问题时开机敲启动菜单键选它，照样能进系统。"
  '';
in
{
  options.custom.refind = {
    enable = lib.mkEnableOption "rEFInd 作为顶层引导入口（systemd-boot 仍管 generation）";

    resolution = {
      width = lib.mkOption {
        type = lib.types.int;
        example = 1920;
        description = ''
          rEFInd 的显示宽度，同时也是生成背景图用的宽度。

          **必须是 UEFI GOP 实际提供的模式**，不是面板原生分辨率就一定能用。
          先按 1920x1080 装上（几乎所有固件都支持），启动后把这里临时设成
          一个无效值（比如 1x1），rEFInd 会列出它支持的全部模式，
          再回来填对的。见 MIGRATION.md 第 6.4 节。
        '';
      };
      height = lib.mkOption {
        type = lib.types.int;
        example = 1080;
        description = "见 width。";
      };
    };

    hostname = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
      defaultText = lib.literalExpression "config.networking.hostName";
      description = "显示在引导画面左上角的主机名（粉色那一串）。";
    };

    bootRows = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "左列标签。**自己补空格对齐**，gen.py 不会替你 pad。";
            };
            value = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "中列内容。习惯上末尾留一个空格，和后面的点线隔开。";
            };
            status = lib.mkOption {
              type = lib.types.str;
              description = "右列状态，例如 [ ONLINE ]。含 ONLINE 或 NOT FOUND 时会渲染成粉色。";
            };
          };
        }
      );
      default = [ ];
      description = ''
        引导画面上那段启动日志。纯装饰，不影响任何启动行为。

        **不要手写这个** —— 在仓库根目录跑 `refind-hwinfo`，它会探测本机硬件
        并写出 `hosts/<主机>/hwinfo.nix`，把那个文件 import 进来即可。
        换了硬件就重跑一次。

        内核那一行不用管，`appendKernelRow` 会自动补，且永远跟着实际内核走。
      '';
    };

    flakeHost = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
      defaultText = lib.literalExpression "config.networking.hostName";
      description = ''
        这台机器在仓库里的名字：`hosts/<这个名字>/` 目录名，同时也是
        `flake.nix` 里 `nixosConfigurations` 的属性名。

        **它不一定等于 `networking.hostName`。** 本机就是个例子：
        目录叫 `hosts/thinkpad/`、flake 属性叫 `thinkpad`，
        而 `networking.hostName` 是 `thinkpad-nixos`。

        只被 `refind-hwinfo` 用来决定默认输出路径和打印下一步命令，
        不影响任何构建产物。
      '';
    };

    appendKernelRow = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        自动在末尾补一行内核版本，取自 `config.boot.kernelPackages.kernel.version`。

        内核版本**刻意不走 refind-hwinfo** —— 它跟着 nixpkgs 滚，
        写进生成的 hwinfo.nix 必然过期，而从求值中的配置取则永远准确。
      '';
    };

    timeout = lib.mkOption {
      type = lib.types.int;
      default = 10;
      description = "菜单停留秒数。";
    };

    espMountPoints = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ config.boot.loader.efi.efiSysMountPoint ];
      defaultText = lib.literalExpression "[ config.boot.loader.efi.efiSysMountPoint ]";
      description = ''
        要写入 rEFInd 的 ESP 挂载点，可以多个。

        单盘单启动就一个。**双盘双启动时要两个** —— Windows 的
        `bcdedit /set {bootmgr} path` 只能指向它自己所在 ESP 内的路径，
        指不到另一块盘上去，所以两个 ESP 各要一份。见 MIGRATION.md 第 6.5 节。

        NVRAM 项只为列表里的**第一个**创建。
      '';
    };

    registerNvram = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        是否用 efibootmgr 建一条 rEFInd 的 NVRAM 项并提到第一顺位。

        关掉的话 rEFInd 只会被写进 ESP，不碰启动顺序 ——
        适合想先手动敲启动菜单验证一轮再决定的场合。
      '';
    };

    extraEntries = lib.mkOption {
      type = lib.types.lines;
      default = "";
      example = lib.literalExpression ''
        '''
          menuentry "Windows 10" {
              icon   /EFI/refind/themes/finn-term/icons/os_win.png
              volume WINESP
              loader /EFI/Microsoft/Boot/bootmgfw.efi
          }
        '''
      '';
      description = ''
        追加到 refind.conf 末尾的 menuentry。

        **`icon` 必须写从 ESP 卷根算起的绝对路径**（`/EFI/refind/...`），
        不能按 `banner` / `icons_dir` 那样写成相对 rEFInd 目录的路径 ——
        rEFInd 这两处的基准不一样。写错不报错，只会静默显示一个内置的
        「加载失败」小方块，而同目录下的功能图标一切正常，很难查。

        Windows 在**另一块盘**上时必须写 `volume`（分区标签或 GUID），
        否则 rEFInd 只会在自己所在的那个 ESP 里找。
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.boot.loader.systemd-boot.enable;
        message = ''
          custom.refind 是**叠在 systemd-boot 之上的一层**，不是替代品：
          rEFInd 只做顶层入口，generation 菜单和回滚仍由 systemd-boot 提供。
          请保持 boot.loader.systemd-boot.enable = true。
        '';
      }
      {
        assertion = !config.boot.loader.efi.canTouchEfiVariables;
        message = ''
          启用 custom.refind 时必须设 boot.loader.efi.canTouchEfiVariables = false。

          否则 systemd-boot 每次 switch 都会把自己设回 UEFI 启动顺序第一位，
          rEFInd 永远轮不到 —— 正好抵消装它的意义。

          改成 false **不会删掉**已存在的 "Linux Boot Manager" NVRAM 项，
          只是不再更新它。那一项就是 rEFInd 出问题时的安全网：
          开机敲启动菜单键选它，照样能正常进系统。
        '';
      }
      {
        assertion = cfg.espMountPoints != [ ];
        message = "custom.refind.espMountPoints 不能为空。";
      }
    ];

    environment.systemPackages = [
      refindSync
      refindHwinfo
      pkgs.efibootmgr # 查启动顺序时要用，装上省得每次 nix shell
    ];
  };
}
