# 虚拟机演练清单

在 Bluefin 上开一台虚拟机，把 [MIGRATION.md](MIGRATION.md) 第 2-6 节
完整走一遍，目的是**把那份文档改对**。

> ## 这份文档怎么用
>
> **命令在 [MIGRATION.md](MIGRATION.md) 里，这里只放虚拟机特有的部分、
> 每一步该验什么、以及对不上时该怀疑什么。**
>
> 刻意不重复那边的命令 —— 两份一旦重复就必然漂移，
> 而我们正在做的事恰恰是验证那份文档。照着它走，这里打勾。
>
> 每个 `[ ]` 是一个检查点。**对得上就继续，对不上就停下来**，
> 把实际输出贴回对话里。

---

## 0. 演练之前先知道三件验证不了的事

虚拟机不是真机，下面三样**在这里过了不代表真机上没问题**：

| 验证不了 | 为什么 | 真机上怎么办 |
|----------|--------|--------------|
| **GOP 分辨率** | OVMF 提供的模式是它自己那套，和真机固件无关 | 真机上按 MIGRATION.md 第 6.4 节重走一遍 |
| **NTFS 脏状态** | 没有真 Windows 去把它弄脏 | 只能真机上碰到才知道 |
| **硬件探测的值** | `refind-hwinfo` 会报虚拟设备 | 真机上重跑一次 |

**但 NVRAM 是真实的。** OVMF 给每台虚拟机一份独立的 varstore，
`efibootmgr` 的增删改、`BootOrder`、rEFInd 抢不抢得到第一位，
行为和真机一致 —— 这恰好是整个流程里最不敢在真机上试错的部分。

---

## 1. 宿主机准备（Bluefin，一次性）

```bash
rpm-ostree status | head -3          # 确认镜像名里有 -dx
ujust dx-group                       # 加进 libvirt / docker / incus / dialout 组
```

- [ ] 镜像名带 `-dx`
- [ ] 跑完 `ujust dx-group` 后**注销重新登录**（组成员身份要新会话才生效）
- [ ] `groups | tr ' ' '\n' | grep libvirt` 有输出
- [ ] `systemctl is-active libvirtd` 或 `virtqemud` 是 active
- [ ] `df -h /var/lib/libvirt/images` 剩余空间 ≥ 60 GB

> 三块虚拟盘标称 128 + 8 + 16 = 152 GB，但 qcow2 是**稀疏分配**，
> 实际占用远小于标称。装完一套带桌面的 NixOS 大约 15-25 GB。

下载 ISO：

- [ ] 从 https://nixos.org/download/ 取 **Minimal ISO**（约 1 GB）
- [ ] `sha256sum` 和下载页比对一致

---

## 2. 建虚拟机

打开 **Virtual Machine Manager**，确认左上角连的是 **QEMU/KVM**
（不是 `QEMU/KVM 用户会话`）。

新建：Local install media → 选刚下的 ISO。

### 2.1 这一步错了要重建整台虚拟机

> ### 必须勾「Customize configuration before install」
>
> 最后一页有个复选框 **Customize configuration before install**，
> **必须勾上**。勾了之后会先进配置界面，在那里把固件改成 UEFI。
>
> **virt-manager 默认是 BIOS，而且固件只能在第一次启动前改。**
> 忘了勾就直接装的话，装出来的是 BIOS 引导的系统 ——
> ESP、rEFInd、`efibootmgr` 全都无从谈起，只能删掉重建。

配置界面里：

| 位置 | 设成 | 为什么 |
|------|------|--------|
| Overview → Firmware | **UEFI x86_64**（不带 secboot 的那个） | NixOS 和 rEFInd 都不签名，Secure Boot 会挡 |
| CPUs → Model | `host-passthrough` | 虚拟机里跑构建，直通快得多 |
| CPUs → vCPU | 8 | 留一半给宿主机 |
| Memory | 12288 MB（12 GB） | NixOS + GNOME 够用，宿主机还剩 20 GB |
| 主盘 → Bus | **VirtIO** | 默认可能是 SATA，慢 |
| NIC → Device model | **virtio** | |
| Video | Virtio 或 QXL | |

- [ ] 勾了 Customize configuration before install
- [ ] Firmware 显示 **UEFI**，不是 BIOS
- [ ] 主盘 128 GB，qcow2，VirtIO
- [ ] **这一步只加主盘**，另外两块后面再加

点 **Begin Installation**。

### 2.2 确认真的是 UEFI

虚拟机起来、进到 ISO 的 shell 之后：

```bash
ls /sys/firmware/efi
```

- [ ] 有输出（目录存在）

> **没有这个目录就是 BIOS 引导**，说明 2.1 那一步漏了。
> 关机、删掉这台虚拟机、从 2.1 重来 —— 固件改不了。

---

## 3. 第一步：单盘，走完 MIGRATION.md 第 2-6 节

从 **MIGRATION.md 第 3.2 节**（Minimal ISO 联网）开始照做。

### 3.1 联网

虚拟机里是 virtio 网卡，插上就通，不用 `nmtui`。

- [ ] `ping -c3 nixos.org` 通

> 文档第 3.2 节写的是 WiFi 场景。**虚拟机里用不上那段** ——
> 如果你觉得文档在这里让人困惑，记下来，那是要改的地方。

### 3.2 分区与格式化（文档第 4 节）

虚拟盘在虚拟机里是 `/dev/vda`（VirtIO），**不是 `/dev/nvme0n1`**。
文档里所有 `/dev/nvme0n1pN` 换成 `/dev/vdaN`。

- [ ] `lsblk` 看到 `vda` 128 G
- [ ] 按第 4.1 节分区：2 GiB ESP + 16 GiB swap + 剩下 Btrfs
- [ ] 按第 4.2 节格式化
- [ ] 按第 4.4 节建四个 subvolume 并挂载
- [ ] `findmnt -R /mnt` 里四个 subvolume 都在，选项含 `compress=zstd:1`

> **这是文档里最可能写错的一段。** 分区命令的起止位置、
> subvolume 的建法、挂载选项的顺序 —— 任何一处和实际不符都记下来。

### 3.3 生成配置（文档第 5.1 节）

- [ ] `nixos-generate-config --root /mnt` 跑通
- [ ] `cat /mnt/etc/nixos/hardware-configuration.nix` 里
      `fileSystems."/"` 的 `options` 含 `subvol=@`、`compress=zstd:1`、`noatime`

> 缺了 `compress=zstd:1` 就说明 3.2 的挂载选项没写对，回去重挂。

### 3.4 接仓库、建 hosts/vm（文档第 5.2 节）

- [ ] `nix-shell -p git --run 'git clone https://github.com/SenorToru/nixos-config /mnt/home/toru/nixos-config'` 成功
- [ ] 建 `hosts/vm/`，把生成的 `hardware-configuration.nix` 拷进去
- [ ] 写 `hosts/vm/default.nix` 和 `hosts/vm/tuning.nix`
- [ ] `flake.nix` 加 `vm` 条目
- [ ] **`git add hosts/vm/`**（新文件，flake 看不见未跟踪的）

`hosts/vm/tuning.nix` 要和 thinkpad 的**完全不同**：

```nix
  # 虚拟机客户机支持。这三项是 tuning.nix 该放的典型内容 ——
  # 只对这台（虚拟）机器成立。
  services.qemuGuest.enable = true;       # 优雅关机、宿主机能读到 IP
  services.spice-vdagentd.enable = true;  # 剪贴板共享、分辨率自适应

  # **不要照抄 thinkpad 的 tuning.nix：**
  #   intel-media-driver  虚拟机没有 Intel 核显
  #   thermald            虚拟机没有 DPTF
  #   vm.swappiness = 100 那是按 7.6 GiB 内存算的
```

- [ ] `custom.flakeHost = "vm";`
- [ ] `custom.refind` 先不要开 —— 第 3.6 步再加

> **这一步顺带验证了「加一台新机器」这个流程本身。**
> 文档第 5.2 节说得够不够让你写出这两个文件？不够就是要改的地方。

### 3.5 装系统（文档第 5.3-5.5 节）

- [ ] `nixos-install --flake /mnt/home/toru/nixos-config#vm` 成功
- [ ] 设了 root 密码
- [ ] **`nixos-enter --root /mnt -c 'passwd toru'`**（第 5.4 节，漏了就登不进去）
- [ ] `chown -R 1000:100 /mnt/home/toru`
- [ ] 重启后能用 toru 登录进桌面

> 第一次构建要下载整棵依赖树，慢是正常的。
> 如果卡在某个包上超过十几分钟，贴回来看看。

### 3.6 装 rEFInd（文档第 6 节）

**这是虚拟机最有价值的一段** —— NVRAM 行为真实，搞坏了删掉重来。

先看基线：

```bash
nix shell nixpkgs#efibootmgr -c efibootmgr
```

- [ ] 记下 `BootOrder` 和 `Linux Boot Manager` 的编号

然后按文档第 9 节的顺序（那节是「把已有机器导入 rEFInd」，
正好就是现在的情形）：

- [ ] `hosts/vm/default.nix` 加 `boot.loader.efi.canTouchEfiVariables = false;`
- [ ] 加 `custom.refind.enable = true;` 和 `resolution`（先随便填，比如 1024x768）
- [ ] `sudo refind-hwinfo` → `git add hosts/vm/hwinfo.nix` → `nrb`
- [ ] `sudo refind-sync`
- [ ] `efibootmgr` 里 rEFInd 在 `BootOrder` 第一位
- [ ] 重启，**rEFInd 菜单出现**
- [ ] 菜单里有 NixOS 图标（**不是约 32×32 的黄黑斜条方块**）
- [ ] 选 NixOS 能进系统

> 出现黄黑斜条方块就是 `icon` 路径不对 —— 那是 rEFInd 内置的
> 「图片加载失败」占位符。见 Lesson-Learn/0013 坑 1。

分辨率：

- [ ] 把 `resolution` 临时设成 `1 1`，`nrb` + `refind-sync` + 重启
- [ ] rEFInd 启动时**列出它支持的全部模式**，记下来
- [ ] 挑一个填回去，再 `nrb` + `refind-sync` + 重启，画面正常

> 这一步在虚拟机里**只验证流程，不验证值** ——
> OVMF 给的模式和真机固件无关。

### 3.7 第一步收尾

- [ ] `migration-check` 跑得起来（虚拟机里没有 dotfiles-state，
      它应该报「状态仓库还没建」，那是正确行为）
- [ ] 关机，**在 virt-manager 里做一个快照**，命名 `第一步完成`

> 做快照是为了第二、三步出问题时能退回来，
> **不是**用来跳过重装 —— 验证装机流程必须每次从头。

---

## 4. 第二步：加第二块盘，验双 ESP

- [ ] 虚拟机关机状态下，virt-manager → Add Hardware → Storage
- [ ] 8 GB，qcow2，VirtIO（会成为 `/dev/vdb`）

在这块盘上造一个**假的 Windows ESP**（不用真装 Windows，
rEFInd 只需要能扫到一个 `.efi`）：

```bash
sudo parted /dev/vdb -- mklabel gpt
sudo parted /dev/vdb -- mkpart ESP fat32 1MiB 100%
sudo parted /dev/vdb -- set 1 esp on
sudo mkfs.fat -F 32 -n WINESP /dev/vdb1
sudo mkdir -p /mnt/winesp && sudo mount /dev/vdb1 /mnt/winesp
sudo mkdir -p /mnt/winesp/EFI/Microsoft/Boot
# 拿 rEFInd 自己的二进制冒充 bootmgfw.efi，只是为了让 rEFInd 有东西可指
sudo cp $(nix eval --raw nixpkgs#refind)/share/refind/refind_x64.efi \
        /mnt/winesp/EFI/Microsoft/Boot/bootmgfw.efi
```

然后按 **MIGRATION.md 第 6.5 节**：

- [ ] `hosts/vm/default.nix` 的 `custom.refind.espMountPoints` 加上 `/mnt/winesp`
- [ ] `custom.refind.extraEntries` 加一条 Windows 的 `menuentry`，
      **带 `volume WINESP`**（在另一块盘上，不写 volume 找不到）
- [ ] `nrb` + `sudo refind-sync`
- [ ] `sudo ls /mnt/winesp/EFI/refind/` 里有东西（两个 ESP 各装了一份）
- [ ] 重启，rEFInd 菜单里**两个图标都在**
- [ ] 选那个假 Windows，能进（会进到 rEFInd 自己，说明链路通了）

> `extraEntries` 里 `icon` 必须写**从 ESP 卷根算起的绝对路径**
> （`/EFI/refind/themes/finn-term/icons/os_win.png`），
> 不能按 `banner` 的规则写相对路径。见 Lesson-Learn/0013 坑 1。

- [ ] 关机，做快照 `第二步完成`

---

## 5. 第三步：加 NTFS 共享盘

- [ ] 关机状态下加第三块盘，16 GB，qcow2，VirtIO（`/dev/vdc`）
- [ ] 按 MIGRATION.md 第 4.3 节格 NTFS
- [ ] 按第 5.2 节把挂载配置写进 `hosts/vm/tuning.nix`（`ntfs3` + `nofail`）
- [ ] `nrb`
- [ ] `findmnt /mnt/share` 显示 `ntfs3`
- [ ] 能往里写文件
- [ ] **测 `nofail`**：关机、在 virt-manager 里把第三块盘移除、开机，
      系统**仍然能正常启动**

> 最后那条是 `nofail` 唯一真正的用途。不测的话，
> 真机上拔掉共享盘会卡在开机。

- [ ] 把盘加回去，确认又能挂上

---

## 6. 收尾

- [ ] `virsh dumpxml <虚拟机名> > /tmp/vm.xml`，存起来备查
- [ ] 把演练中改过的 `MIGRATION.md` 一次性提交
- [ ] `hosts/vm/` 提交进仓库（长期保留当回归测试）

> `hosts/vm/` 留着的价值：以后改 `modules/` 里的共用配置，
> 可以先 `nix build .#nixosConfigurations.vm...` 验一遍。
> **它是目前唯一的第二台主机**，存在本身就能挡住
> 「把本机专属的东西写进 modules/」这类错误。

---

## 7. 然后进阶段二

第一步那台虚拟机**不要删**。从那里开始往里搬开发环境：

- 每个项目一个 `flake.nix` devShell + `.envrc`
- 工具链在项目里，系统里只放跨项目的（编辑器、git、shell）
- 容器只用于有状态的服务（Postgres/Redis/MinIO），
  **任何编译器、解释器、CLI 工具一律进 devShell**
- pnpm + Node，wrangler 进项目的 `devDependencies`

验收标准：**一个真实的 Cloudflare 项目能 `wrangler dev` 也能 `wrangler deploy`**，
而且把虚拟机删掉重装之后，`git clone` + `direnv allow` 就能继续开发，
**不需要任何手工步骤**。

最后那条才是真正证明了「换个地方还能用」。
