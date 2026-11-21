{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.custom.voiceDictation;

  # llama.cpp：识别（Qwen3-ASR）和整理（Qwen3.5-9B）共用这一份。
  #
  # 主机声明了 CUDA 架构就编 CUDA 版，只编那一个架构 ——
  # nixpkgs 默认会给所有支持的架构各编一遍，慢好几倍，而这台只有一块卡。
  # sm_120 一份在 asus 上实测 6 分钟（16 线程），闭包约 1 GB（主要是 cuBLAS）。
  # 二进制缓存里没有 CUDA 版（unfree），所以第一次 nrb 会在本机编；
  # 之后只有 nixpkgs 里 llama-cpp 或它的依赖变了才会重编。
  #
  # 没声明架构就用缓存里现成的 CPU 版：能用，但整理一段要十几秒到几十秒。
  llamaPackage =
    if cfg.cudaArchitectures == [ ] then
      pkgs.llama-cpp
    else
      (pkgs.llama-cpp.override { cudaSupport = true; }).overrideAttrs (old: {
        cmakeFlags = (lib.filter (f: !lib.hasPrefix "-DCMAKE_CUDA_ARCHITECTURES" f) old.cmakeFlags) ++ [
          (lib.cmakeFeature "CMAKE_CUDA_ARCHITECTURES" (lib.concatStringsSep ";" cfg.cudaArchitectures))
        ];
      });
in
{
  # 语音输入。默认关；asus 在 hosts/asus/default.nix 打开。
  # 规格是 VOICE_DICTATION.md，实际实现与理由见 Lesson-Learn/0019_VOICE_DICTATION.md。
  #
  # 分三处：
  #   这里                  选项、llama.cpp 的构建、ydotool（系统服务 + 用户组）
  #   home/voice-dictation.nix  脚本、模型清单、提示词、F8 / F9 两条快捷键
  #   home/desktop-prefs.nix    把两条快捷键的路径追加进 custom-keybindings 列表
  # 用户组加在 hosts/<主机>/default.nix 的 extraGroups（模块里不写用户名）。
  #
  # enable = false 再 switch，就回到没有语音输入的状态：快捷键、包、
  # ydotoold 服务、ydotool 组一起消失。~/.cache/voice-dictation 里的模型
  # 留在磁盘上，没有任何东西会去读它。
  #
  # 两台主机都要 import 这个文件：home/ 里的文件读
  # osConfig.custom.voiceDictation.enable，选项不存在就求值失败。

  options.custom.voiceDictation = {
    enable = lib.mkEnableOption "语音输入（F8 开始 / 结束，F9 贴原文）";

    cudaArchitectures = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "120" ];
      description = ''
        llama.cpp 要编的 CUDA 架构（CMAKE_CUDA_ARCHITECTURES 的写法，不带点）。
        绑在显卡上，写在 hosts/<主机>/tuning.nix。空列表表示用 CPU 版。
      '';
    };

    llamaPackage = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      internal = true;
      default = llamaPackage;
      defaultText = lib.literalMD "按 `cudaArchitectures` 选 CUDA 版或 CPU 版的 llama-cpp";
      description = "home/voice-dictation.nix 用的 llama.cpp。";
    };
  };

  config = lib.mkIf cfg.enable {
    # 粘贴键靠 ydotool 发。GNOME Wayland 不提供 wtype 要的虚拟键盘协议，
    # ydotool 走内核的 /dev/uinput，所以哪个窗口都收得到。
    #
    # 用 nixpkgs 现成的 programs.ydotool（nixos/modules/programs/ydotool.nix）：
    # 系统服务 ydotoold（root、加固过），socket 在 /run/ydotoold/socket，
    # 属组 ydotool、权限 0660。用户要进 ydotool 组才能用，
    # 组加在 hosts/<主机>/default.nix。**加组之后要注销再登录一次才生效。**
    #
    # 只送 Shift+Insert 这一个组合键，不送任何文字（ydotool 打不出中文和假名，
    # 文字一律走剪贴板）。
    programs.ydotool.enable = true;
  };
}
