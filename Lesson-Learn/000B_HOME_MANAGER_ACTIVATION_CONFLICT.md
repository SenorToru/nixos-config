# home-manager 激活失败：Existing file would be clobbered

> 日期：2026-09-17　|　触发改动：给 `home/toru.nix` 加 `xdg.mimeApps`
> （见 [000A_NIXOS_CONFIG_AUDIT.md](000A_NIXOS_CONFIG_AUDIT.md) 的「修复 3」）

## 问题症状

`nixos-rebuild switch` 跑完，构建全部成功，但末尾报：

```
restarting the following units: home-manager-toru.service, polkit.service
Failed to restart home-manager-toru.service
warning: the following units failed: home-manager-toru.service

× home-manager-toru.service - Home Manager environment for toru
     Active: failed (Result: exit-code)

hm-activate-toru[21081]: Existing file '/home/toru/.local/share/applications/mimeapps.list' would be clobbered
systemd[1]: home-manager-toru.service: Failed with result 'exit-code'.

Command 'systemd-run ... switch-to-configuration switch' returned non-zero exit status 4.
```

## 根本原因

home-manager 在链接文件之前会跑一个 `checkLinkTargets` 阶段：
**凡是目标路径上已经存在一个「不是 HM 自己管理的普通文件」，就整个激活中止。**
这是有意设计的保护措施，防止 HM 悄悄覆盖用户手写的配置。

本次踩到它，是因为 `xdg.mimeApps` **同时管理两个路径**：

```
~/.config/mimeapps.list                        ← 主位置（XDG 规范当前推荐）
~/.local/share/applications/mimeapps.list      ← 已废弃的旧位置，HM 也会建一个 symlink 指过去
```

排查时只检查了第一个（确实不存在），第二个路径上却躺着一个
**0 字节的空文件**（2026-09-06 生成，大概是某个应用随手建的）。
HM 不看内容、只看「这是不是我管的」，所以空文件照样挡路。

可以用这条命令提前把 HM 想管理的全部文件和家目录现状对一遍：

```bash
nix build .#nixosConfigurations.thinkpad.config.home-manager.users.toru.home.activationPackage \
  --out-link /tmp/hm

cd /tmp/hm/home-files && find . -type l -o -type f | sed 's|^\./||' | while read -r rel; do
  t="$HOME/$rel"
  if   [ -e "$t" ] && [ ! -L "$t" ]; then echo "会冲突（普通文件已存在）: ~/$rel"
  elif [ -L "$t" ];                  then echo "已是 symlink（可安全替换）: ~/$rel"
  else                                    echo "新建: ~/$rel"
  fi
done
```

## 最坑的地方：这是「半成功」状态

`nixos-rebuild switch` 分两个阶段：

```
1. 系统层激活   → /etc、fonts、systemPackages、/etc/profiles/per-user/<user>
2. 重启 home-manager-<user>.service → 家目录里的配置文件链接
```

**阶段 2 失败时，阶段 1 已经切过去了。**
所以「命令报错了」绝不等于「什么都没变」。本次的实际状态是：

| 改动 | 所在层 | 是否生效 |
|------|--------|----------|
| 字体族名修正 | 系统层 | ✅ 已生效 |
| `vim` / `vi` / `nvim` 统一 | 系统层（`useUserPackages` 把 HM 的包放进 `/etc/profiles`） | ✅ 已生效 |
| 默认浏览器（mimeapps.list） | home 层 | ❌ 没生效 |
| nvim 配置文件链接 | home 层 | ❌ 没重新链接 |

判断 home 层到底有没有生效：

```bash
ls -la ~/.config/nvim/init.lua   # 看 symlink 指向哪个 home-manager-files hash
ls -la ~/.config/mimeapps.list   # 不存在 = home 层没生效
systemctl status home-manager-toru.service
```

## 解决方法

### 1. 移走挡路的文件（一次性）

```bash
mv ~/.local/share/applications/mimeapps.list /tmp/mimeapps.list.bak
```

本次那个文件是 0 字节，无信息损失。**动手前务必先看一眼内容**，
不是每次都这么安全。

### 2. 从根上避免（永久）

在 `hosts/thinkpad/default.nix` 里加：

```nix
home-manager.backupFileExtension = "hm-bak";
```

加上之后，HM 遇到挡路的文件会把它改名成 `<原名>.hm-bak` 再继续，
不再中断整个激活。

## 为什么选 backupFileExtension 而不是 force

HM 提供了三条路：

| 做法 | 效果 | 评价 |
|------|------|------|
| `xdg.configFile."mimeapps.list".force = true` | 直接覆盖，原文件丢失 | 只能一个一个文件写，而且真的会丢数据 |
| `home-manager.backupCommand` | 自定义命令处理 | 灵活，但要自己写脚本，过度设计 |
| `home-manager.backupFileExtension`（选此） | 自动改名备份后继续 | 一行配置全局生效，原文件保留成 `.hm-bak` |

关键权衡：**「系统层切了、home 层没切」的半成功状态，比「多出几个 `.hm-bak` 文件」
危险得多。** 前者会让人误以为配置没生效而反复重试，或者更糟——
误以为配置生效了而基于错误前提继续排查。后者只是几个可以随手删的备份文件。

## 后续注意事项

1. **看到 `warning: the following units failed: home-manager-toru.service`，
   不要只看命令退出码就下结论。** 必须单独确认 home 层状态（上面有命令）。

2. **`backupFileExtension` 只解决「文件冲突」这一类失败。**
   其它原因（选项求值出错、activation script 报错）仍会失败，
   仍然是半成功状态，判断方法一样。

3. **加了新的 `xdg.*` / `home.file` 配置后，先跑上面那段预检脚本。**
   比失败一次再回头查快。

4. **`.hm-bak` 文件会累积。** 偶尔 `find ~ -name '*.hm-bak'` 清一下。

## 相关文档

- [000A_NIXOS_CONFIG_AUDIT.md](000A_NIXOS_CONFIG_AUDIT.md) —— 触发本次冲突的 `xdg.mimeApps` 改动
- [0003_PLUGIN_AND_FONT_ISSUES.md](0003_PLUGIN_AND_FONT_ISSUES.md) —— 另一条 HM 相关教训：不要直接编辑 `~/.config/nvim/`
