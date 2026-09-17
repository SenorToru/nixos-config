{ ... }:

{
  # ============================================
  # 登录 shell：zsh
  # ============================================
  # 这个文件**只放必须在系统层的部分**。交互体验（提示符、补全插件、历史、
  # 别名、direnv、tmux 等）全部在 home/toru.nix 里，不在这里重复声明 ——
  # 见 CLAUDE.md「不要在系统层和 home 层各声明一次同一个程序」。
  #
  # 为什么系统层也必须 enable 一次：
  #   1. users.users.<名字>.shell 指向的可执行文件必须登记进 /etc/shells，
  #      否则 chsh 和部分 PAM 场景会拒绝它。programs.zsh.enable 会自动登记。
  #   2. 它生成 /etc/zshrc 与 /etc/zprofile，在里面 source /etc/set-environment
  #      （系统 PATH）。少了这一步，zsh 会拿到一个缺少
  #      /run/current-system/sw/bin 的 PATH。
  #   3. 它负责跑一次 compinit。home 层因此把 enableCompletion 关掉，
  #      避免每开一个终端重复构建补全缓存。
  programs.zsh.enable = true;

  # 注意：这里**不写** users.users.<名字>.shell。
  # 那一句把模块钉死在某个具体用户名上，和本模块「任何机器都能直接 import」
  # 的定位冲突。登录 shell 的指派放在声明该用户的地方，
  # 即 hosts/<主机>/default.nix。

  # bash 保持完全可用，只是不再是任何人的登录 shell。
  # 这是刻意的：AI 编码助手常常直接跑 `bash -c`，
  # home/toru.nix 里把 bash 和 zsh 配成了同一套基线。

  # ============================================
  # 分页器
  # ============================================
  # -F：内容不足一屏就直接输出并退出
  # -R：保留 ANSI 颜色转义
  # -X：不发终端的 init/deinit 序列，退出后输出留在屏幕上
  #
  # 对人是少按一次 q；对自动化跑 shell 的 AI 则是**不会卡在分页器里等输入** ——
  # 这是非交互场景下最常见的一种假死。
  # FRX 也正是 git 自己在 LESS 未设置时使用的默认值，所以显式设成同一套，
  # 不会改变 git log / git diff 现有的行为。
  #
  # 用 sessionVariables 而不是 variables：前者写进 /etc/pam/environment，
  # 是会话级的，任何进程任何 shell 都继承；后者只进 /etc/set-environment，
  # 要靠 shell 去 source。非交互场景下前者更可靠。
  environment.sessionVariables = {
    PAGER = "less -FRX";
    LESS = "-FRX";
  };
}
