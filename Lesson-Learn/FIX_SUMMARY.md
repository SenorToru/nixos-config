修复总结：LSP 配置弃用错误

问题
在 Neovide 中打开 .nix 文件时出现以下错误：
  The `require('lspconfig')` "framework" is deprecated, use vim.lsp.config
  (see :help lspconfig-nvim-0.11) instead.
  Feature will be removed in nvim-lspconfig v3.0.0

根本原因
LSP 配置使用的是旧的 require("lspconfig") API，已在 Neovim 0.11+ 中被弃用，
应该使用新的 vim.lsp.start() API。

解决方案
在两个位置更新了 formatting.lua：

1. 本地 Neovim 配置
   文件：/home/toru/.config/nvim/lua/plugins/formatting.lua
   - 替换：require("lspconfig") → vim.lsp.start()
   - 实现：FileType 自动命令按需启动 nil
   - 使用：vim.lsp.protocol.make_client_capabilities() 直接获取
   - 保留：所有 LSP 快捷键和格式化功能

2. NixOS 配置
   文件：/home/toru/nixos-config/home/toru.nix (programs.neovim 部分)
   - 更新：formatting.lua 插件规范使用新 API
   - 同步：与本地 Neovim 配置一致

变更内容

本地文件已更新：
  /home/toru/.config/nvim/lua/plugins/formatting.lua
  - 移除：pcall(require, "lspconfig") 包装器
  - 移除：lspconfig.nil_ls.setup() 框架调用
  - 新增：vim.lsp.start() 直接启动 LSP
  - 新增：FileType 自动命令激活 nil
  - 保留：所有快捷键 (gd, gD, K, <leader>rn, <leader>ca, <leader>f)
  - 保留：nixfmt 格式化命令
  - 保留：LSP 能力来自 cmp_nvim_lsp

NixOS 配置已更新：
  /home/toru/nixos-config/home/toru.nix
  - 更新：formatting.lua 文本块采用新实现
  - 准备好：下次 nixos-rebuild switch 部署

Git 提交文档：
  /home/toru/nixos-config/GIT_COMMIT_MESSAGE.txt
  - 新提交消息："fix: Replace deprecated lspconfig API..."
  - 记录：修改原因和测试情况

验证

测试已完成：
  - nix flake check：通过 ✅ (all checks passed!)
  - Neovim 启动：通过 ✅ (无弃用警告)
  - 配置语法：有效 ✅

功能保留：
  - LSP 快捷键正常工作
  - Nix 文件格式化功能启用
  - 代码补全和诊断正常
  - Copilot 集成不受影响

下一步操作

应用更改到完整系统：

1. 用当前 Neovide 测试：
   neovide /home/toru/nixos-config
   # 打开任何 .nix 文件 - 不应该出现错误

2. 应用 NixOS 配置：
   cd /home/toru/nixos-config
   sudo nixos-rebuild switch --flake .#thinkpad

3. 提交更改：
   git add home/toru.nix
   git commit -F GIT_COMMIT_MESSAGE.txt

补充说明

- 本地 Neovim 配置 (/home/toru/.config/nvim/) 立即生效，
  可以立即修复弃用错误。

- NixOS/HomeManager 配置将在运行 sudo nixos-rebuild switch 时
  完全应用，会从 Nix 配置重新生成 ~/.config/nvim/ 文件。

- 两种配置方法的实现完全相同，确保一致性。

- 新的 vim.lsp.start() 方式向前兼容未来 Neovim 版本，
  完全避免使用已弃用的 lspconfig 框架。
