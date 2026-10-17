# GNOME 候选词框不读 fcitx5 主题

## 问题症状

中文（Rime）和日文（Mozc）的候选词又细又淡，融进当前主题的底色里。
按主题生成了 fcitx5 classic UI 的 `theme.conf`（Sarasa Gothic J 18、反差字、
更亮的选中底、艳色边），`nrb`、重启、`theme` 都跑过，画面完全没变。

家目录里的文件其实是对的：`~/.config/fcitx5/conf/classicui.conf` 和
`~/.config/fcitx5/themes/stylix/theme.conf` 都是指向 store 的链接，
内容就是那套配色。

## 根本原因分析

GNOME 上画出候选词的是扩展 `kimpanel@kde.org`（`modules/desktop-gnome.nix`
装的，`enabled-extensions` 里开着），不是 fcitx5 的 classic UI。

kimpanel 的 `panel.js` 用 GNOME Shell 的 `St` 控件画一个 popup。
颜色走 Shell 主题里 `.popup-menu` 那一组规则，也就是 stylix 生成的
`~/.local/share/themes/Stylix/gnome-shell/gnome-shell.css`。
选中行只是在底色上再压暗一档，所以亮色主题更难看清。

字号不在那份 CSS 里。`lib.js` 的 `getTextStyle()` 读
`org.gnome.shell.extensions.kimpanel` 的 `font`，拆成 Pango 描述后写成
**inline style**。当时这个键是 `Sarasa Fixed CL Ultra-Light 11`：
极细、11 号。inline style 盖过样式表，所以只改 CSS 的 `font-size` 不会生效。

`fcitx5-remote -r`、重启、切换主题都只会让 classic UI 或 Shell 主题重载。
classic UI 的 `Theme=stylix` 没有人拿去画这块面板。

## 已实施的修复

`home/fcitx-candidate.nix` 仍按每套 stylix 主题算同一组颜色，写两处：

- classic UI 的 `theme.conf`：kimpanel 没在画的时候用（别的桌面）
- 把更具体的选择器接到 stylix 那份 `gnome-shell.css` 末尾：
  `.popup-menu-content.kimpanel-popup-content` 的底和 2px 艳色边，
  `.popup-menu-item.kimpanel-candidate-item:active` 的更亮选中底，
  以及候选文字上的 `text-shadow`（荧光在字上，不在整块面板上）。
  `:active` 要单独再写一遍阴影，它是另一套样式节点。
  选择器比 stylix 的 `.popup-menu-item:active` 多一个类名，
  扩展自己的 `stylesheet.css` 后加载也盖不住

字号改在 `home/toru.nix` 的 dconf：`Sarasa Gothic J 14`。
`vertical` 仍是 true。

接到 Shell 主题上的办法是 `mkForce` 最终的 `home.file` 链接目标
（先 `cat` stylix 的 css，再接自己的那段）。不要去 `mkForce`
`xdg.dataFile` 的 `source`，那会把 stylix 的产物换掉，同时又要读它。

`theme` 切换时，Shell 主题文件变了，原有的 user-theme 重载钩子会吃到新颜色。
候选框要重新点开一次。

## 为什么这样解决

两套输入法在 GNOME 上共用 kimpanel 这一块，改一处两边一起变。
颜色放在 home 模块里，specialisation 会按那套调色板重算，换主题不用单独维护。
classic UI 那份留着，是因为关掉 kimpanel 或换桌面之后它才是被画出来的那层。

荧光用 `St.Label` 支持的 `text-shadow`，画在候选词上。
整块面板不再加 `box-shadow`。classic 主题没有文字阴影，那边仍然只有亮边。

## 后续注意事项

- 判断「候选窗改没改到」先看谁在画。`gnome-extensions info kimpanel@kde.org`
  是 ACTIVE 的话，去查 dconf 的 `font` 和 `gnome-shell.css` 末尾有没有
  `kimpanel-popup-content`。`classicui.conf` 内容正确不能说明画面会变。
- 字号只改 dconf。验证族名用 `fc-match "Sarasa Gothic J"`，
  不要把 `Sarasa Gothic J 14` 整串丢给 `fc-match`。
- `dconf read /org/gnome/shell/extensions/kimpanel/font` 在改动生效后应是
  `'Sarasa Gothic J 14'`。
- 扩展的 `stylesheet.css` 在系统扩展目录里，不要为了配色去改那份。
  它不跟着主题走。

## 相关文档

- [README.md](../README.md) 的 `home/fcitx-candidate.nix` 一行
- [MIGRATION.md](../MIGRATION.md) 里 `classicui.conf` 为什么不进 dotfiles-state
