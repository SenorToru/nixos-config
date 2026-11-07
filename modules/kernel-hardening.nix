# 两台机器都成立的内核攻击面收紧。内核选哪个包写在 hosts/<主机>/default.nix。
#
# OpenAI 2026-11 那次扫描打的是内核 master，948 是「有利用代码的不同缺陷」
# 的计数，不是已经进稳定版的补丁数。当时十天里上游合并的只是其中一小部分。
# 把 nixpkgs 换成 unstable 也装不上那批未合并的修复，所以这里不引第三方源。
{
  # NixOS 的 nixpkgs 内核没有 kernel.unprivileged_userns_clone 这个 sysctl
  # （那是 Ubuntu 的下游补丁）。写成 boot.kernel.sysctl 会让 systemd-sysctl 失败。
  #
  # 也不能把 security.allowUserNamespaces 设成 false。那会把 user.max_user_namespaces
  # 写成 0，非特权进程和 rootless 容器都建不了用户命名空间。本机 nix.settings.sandbox
  # 是 true，NixOS 对此有断言，构建会直接失败。Flatpak（bubblewrap）同样依赖它。
  # 保持默认打开，是「收紧攻击面」和「rootless 还能跑」同时成立的做法。
  security.allowUserNamespaces = true;

  boot.kernel.sysctl = {
    # 普通用户不能再新建 io_uring。io_uring 是近几年本地提权的高发入口。
    # 判定用的是当前用户命名空间里的 CAP_SYS_ADMIN：Nix 构建沙箱、Flatpak、
    # rootless 容器在自己的命名空间里仍是 root，io_uring 继续可用。
    # 宿主机上的普通进程拿到 EPERM，Chrome / Steam 会退回别的 I/O。
    "kernel.io_uring_disabled" = 1;

    # 非特权进程不能再用 perf 事件。本机内核默认是 2（禁止看内核），这里收到 3
    # （非特权完全不可用）。要分析性能时用 sudo。
    "kernel.perf_event_paranoid" = 3;

    # 禁止运行中再加载另一份内核镜像。不用 security.protectKernelImage，
    # 那个选项还会加上 nohibernate，会连带关掉休眠。
    "kernel.kexec_load_disabled" = 1;

    # 只能 ptrace 自己的子进程。gdb 从命令行拉起的进程不受影响，
    # gdb -p 附到已经在跑的进程需要 root。显式写上，避免以后换内核默认值又放开。
    "kernel.yama.ptrace_scope" = 1;
  };

  # 下面几项已经是这份 nixpkgs 内核或 NixOS 的默认，不重复写：
  #   kernel.kptr_restrict = 1          NixOS 的 sysctl 模块
  #   kernel.dmesg_restrict = 1         CONFIG_SECURITY_DMESG_RESTRICT
  #   kernel.unprivileged_bpf_disabled = 2   CONFIG_BPF_UNPRIV_DEFAULT_OFF
  #   vm.unprivileged_userfaultfd = 0
  # 也不开 security.lockKernelModules：启动完成后再禁模块，会挡住晚加载的
  # NVIDIA / 固件相关模块。
}
