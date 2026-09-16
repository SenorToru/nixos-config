问题分析：未解决的 Neovim 配置问题

已识别的问题

1. 插件加载错误（反复出现）
   错误：Invalid spec module: `plugins`
   预期：`table` of specs，但返回 nil
   
   原因：nvim/lua/plugins/init.lua 返回 nil（缺少 return 语句）
   
   解决方案：在 home/toru.nix 配置中添加 return {}
   
   关键教训：
   - 不要尝试直接编辑 /home/toru/.config/nvim/
   - 这些是由 HomeManager 通过 Nix 管理的符号链接
   - 所有修改必须在 /home/toru/nixos-config/home/toru.nix 中进行
   - 修改仅在 `sudo nixos-rebuild switch` 后生效

2. 字体解析错误（Neovide）
   错误：Failed to parse guifont: Invalid size
   
   根本原因：错误的 guifont 格式
   - 错误："Sarasa Mono:h12,Noto Sans Mono CJK SC:h12"
     问题：字体名中有空格，不支持逗号分隔的备选字体
   - 正确："SarasaMono:h12"
     规则：字体名中无空格，无字体间的逗号
   
   解决方案：改用简单的单字体格式："SarasaMono:h12"

关键工作流提醒

从不直接编辑这些文件：
  ✗ /home/toru/.config/nvim/
  ✗ /home/toru/.config/nvim/lua/
  ✗ /home/toru/.config/ 下的任何文件

始终编辑这些文件：
  ✓ /home/toru/nixos-config/home/toru.nix (HomeManager)
  ✓ /home/toru/nixos-config/modules/*.nix (系统)
  ✓ /home/toru/nixos-config/Lesson-Learn/ (文档)

为什么？
- ~/.config/nvim/ 中的文件由 home/toru.nix 通过 HomeManager 生成
- 它们是指向 /nix/store/ 的符号链接（只读）
- 直接编辑会在下次 `home-manager switch` 时被覆盖
- 唯一持久化修改的方式：修改 home/toru.nix 后重建

部署序列

1. 修改 /home/toru/nixos-config/home/toru.nix
2. 使用以下命令验证：nix flake check
3. 应用修改：sudo nixos-rebuild switch --flake .#thinkpad
4. 验证结果：neovide /home/toru/nixos-config

所做的 NixOS 配置修改

文件：/home/toru/nixos-config/home/toru.nix

修改 1 - 修复 plugins/init.lua：
  修改前：
    "nvim/lua/plugins/init.lua" = {
      text = ''
        -- 仅注释
      '';
    };
  
  修改后：
    "nvim/lua/plugins/init.lua" = {
      text = ''
        -- 注释
        return {}
      '';
    };

修改 2 - 修复 guifont 格式：
  修改前：
    vim.opt.guifont = "Sarasa Mono:h12,Noto Sans Mono CJK SC:h12"
    问题：有空格、逗号、多字体格式
  
  修改后：
    vim.opt.guifont = "SarasaMono:h12"
    正确：无空格、单一字体、有效格式

验证
- nix flake check：通过 ✅
- 配置语法：有效 ✅
- 准备就绪：sudo nixos-rebuild switch

下一步

1. 应用配置：
   cd /home/toru/nixos-config
   sudo nixos-rebuild switch --flake .#thinkpad

2. 在 Neovide 中验证：
   neovide /home/toru/nixos-config
   应该无插件/字体错误地加载

3. 提交更改：
   git add home/toru.nix
   git commit -F GIT_COMMIT_MESSAGE.txt

关键学习

1. HomeManager 管理所有 ~/.config/ 文件
   - 从不直接编辑它们
   - 始终通过 Nix 配置修改

2. Neovide 中的 guifont 格式非常严格
   - 格式："FontName:h12"（字体名中无空格）
   - 使用单一字体，不支持备选字体
   - 无效：字体有空格 "Font Name:h12"
   - 无效：多字体逗号分隔 "Font:h12,Font2:h12"
   - 有效：单字体 "FontName:h12"

3. Nix Store 的文件符号链接
   - 在 /nix/store/ 中只读
   - 在重建时从源代码重新生成
   - 可能看起来被修改但实际修改不会持久化

4. Nix flake check 验证一切
   - 总是在重建前运行
   - 早期捕获语法错误
   - 节省重建时间

Key Learnings

1. HomeManager manages all ~/.config/ files
   - Never edit them directly
   - Always modify via Nix configuration

2. Guifont format in Neovide is strict
   - Format: "FontName:h12" (no spaces in font name)
   - Use single fonts, not fallbacks
   - Invalid: "Font Name:h12" (space)
   - Invalid: "Font:h12,Font2:h12" (comma)
   - Valid: "FontName:h12"

3. File symlinks from Nix Store
   - Read-only in /nix/store/
   - Regenerated from source on rebuild
   - Can appear to be modified but changes don't persist

4. Nix flake check validates everything
   - Always run before rebuild
   - Catches syntax errors early
   - Saves rebuild time
