{
  pkgs,
  ...
}:

let
  baseExtensionPolicies = {
    ExtensionUpdate = true;
    ExtensionSettings = {
      "*" = {
        installation_mode = "allowed";
      };
      "uBlock0@raymondhill.net" = {
        install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
        installation_mode = "force_installed";
      };
      "78272b6fa58f4a1abaac99321d503a20@proton.me" = {
        install_url = "https://addons.mozilla.org/firefox/downloads/file/4885390/latest.xpi";
        installation_mode = "force_installed";
      };
      "addon@darkreader.org" = {
        install_url = "https://addons.mozilla.org/firefox/downloads/latest/darkreader/latest.xpi";
        installation_mode = "force_installed";
      };
      "sponsorBlocker@ajay.app" = {
        install_url = "https://addons.mozilla.org/firefox/downloads/latest/sponsorblock/latest.xpi";
        installation_mode = "force_installed";
      };
      "{b9acf540-acba-11e1-8ccb-001fd0e08bd4}" = {
        install_url = "https://addons.mozilla.org/firefox/downloads/file/4997872/latest.xpi";
        installation_mode = "force_installed";
      };
    };
  };

in
{
  home.username = "toru";
  home.homeDirectory = "/home/toru";
  home.stateVersion = "26.05";

  # ============================================
  # Firefox（系统默认浏览器）
  # ============================================
  programs.firefox = {
    enable = true;
    policies = baseExtensionPolicies;
  };

  # 把 Firefox 设为默认浏览器。
  # 之前没有任何模块声明过默认浏览器，GNOME 便自行选了 Epiphany
  # （`xdg-settings get default-web-browser` 会返回 org.gnome.Epiphany.desktop），
  # 于是从终端 / 其它应用打开链接都会跳到 GNOME Web。
  #
  # xdg.mimeApps 会接管 ~/.config/mimeapps.list。
  # BROWSER 变量给不读 mimeapps.list 的 CLI 程序（如部分 TUI）用。
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html" = [ "firefox.desktop" ];
      "application/xhtml+xml" = [ "firefox.desktop" ];
      "x-scheme-handler/http" = [ "firefox.desktop" ];
      "x-scheme-handler/https" = [ "firefox.desktop" ];
      "x-scheme-handler/about" = [ "firefox.desktop" ];
      "x-scheme-handler/unknown" = [ "firefox.desktop" ];
    };
  };

  home.sessionVariables.BROWSER = "firefox";

  # ============================================
  # Neovim 配置 (HomeManager)
  # ============================================
  # 注 1：插件由 lazy.nvim 独立管理，不通过 HomeManager。
  # 注 2：这是全系统**唯一**的 neovim 声明处。modules/development.nix 里
  #       曾经还有一份系统级 programs.neovim，导致 vim / vi 指向另一个不带
  #       extraPackages 的 neovim，Copilot 在那个 neovim 下必然离线。
  #       别再把 programs.neovim 加回 development.nix。
  programs.neovim = {
    enable = true;

    # 以下三项从 development.nix 迁移过来，确保 nvim / vim / vi / $EDITOR
    # 全部指向这一个带 extraPackages 的 neovim。
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;

    extraPackages = with pkgs; [
      # 格式化和 linting
      nixfmt
      nil

      # Node.js (Copilot 需要)
      nodejs_24

      # GitHub CLI (Copilot 认证)
      # 如果仅使用 VSCode 认证，可注释掉此行
      github-cli

      # Copilot 语言服务器需要 unzip
      unzip

      # 其他 LSP 依赖
      lua-language-server

      # Claude Code CLI
      # claudecode.nvim 是从 Neovim 内部 spawn `claude` 的，所以必须放进
      # extraPackages（nvim 的 wrapper PATH），只装进 systemPackages 不够。
      claude-code
    ];
  };

  # Neovim 配置文件 (通过 xdg.configFile 管理)
  xdg.configFile = {
    "nvim/init.lua" = {
      text = ''
        -- ============================================
        -- Neovim 初始化配置 (由 HomeManager 管理)
        -- ============================================

        -- 设置 <leader> 键
        vim.g.mapleader = " "
        vim.g.maplocalleader = " "

        -- 基础选项
        vim.opt.tabstop = 2
        vim.opt.softtabstop = 2
        vim.opt.shiftwidth = 2
        vim.opt.expandtab = true
        vim.opt.autoindent = true
        vim.opt.smartindent = true
        vim.opt.number = true
        vim.opt.relativenumber = true
        vim.opt.wrap = false
        vim.opt.signcolumn = "yes"

        -- Neovide 特定配置
        if vim.g.neovide then
          -- 使用 Sarasa Mono J (日文编程字体，支持中日韩)
          -- 字体名必须与系统安装的字体名完全匹配
          vim.opt.guifont = "Sarasa Mono J:h12"
          vim.g.neovide_cursor_animation_length = 0.13
          vim.g.neovide_cursor_trail_size = 0.8
        end

        -- 加载 lazy.nvim 配置
        require("config.lazy")
      '';
    };

    "nvim/lua/config/lazy.lua" = {
      text = ''
        -- ============================================
        -- Lazy.nvim 插件管理器配置
        -- ============================================

        local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
        if not (vim.uv or vim.loop).fs_stat(lazypath) then
          vim.fn.system({
            "git",
            "clone",
            "--filter=blob:none",
            "https://github.com/folke/lazy.nvim.git",
            "--branch=stable",
            lazypath,
          })
        end
        vim.opt.rtp:prepend(lazypath)

        require("lazy").setup({
          spec = {
            { import = "plugins" },
          },
          -- 禁用启动时的更新检查提示，避免交互式提示
          checker = { enabled = false },

          git = {
            -- 默认 120 秒。本机上行/下行都很慢（实测 ~80 KiB/s），
            -- snacks.nvim 这种 1.3 万对象的仓库根本装不完就被杀。
            timeout = 600,

            -- 默认 true，即用 `git clone --filter=blob:none` 做**部分克隆**：
            -- 初次只拉 commit 和 tree，blob 留到 checkout 时按需从网络取。
            -- 正常网速下这是优化，慢网下却是灾难 —— checkout 变成第二次
            -- 网络往返，一旦中断就留下「clone 成功但工作区是空的」目录，
            -- 报错写作 "Clone succeeded, but checkout failed"。
            -- 关掉它改为完整克隆：一次把所有对象拉全，checkout 纯本地操作，
            -- 代价是初次下载量变大，换来的是可靠。
            filter = false,
          },
        })
      '';
    };

    "nvim/lua/plugins/copilot.lua" = {
      text = ''
        -- ============================================
        -- GitHub Copilot 配置 (copilot.lua)
        -- ============================================
        -- 注意：不要再加 copilot-cmp。
        --   1. copilot-cmp 已停止维护（最后提交 2024-12），内部使用
        --      client.is_stopped()，在 Neovim 0.11+ 已废弃，启动时会报
        --      "client.is_stopped is deprecated"。
        --   2. copilot-cmp 要求关闭 suggestion / panel 模块，与下面的
        --      行内建议（ghost text）冲突。
        -- 现在统一使用 copilot.lua 自带的 suggestion 模块。

        return {
          {
            "zbirenbaum/copilot.lua",
            lazy = false,
            config = function()
              require("copilot").setup({
                -- Node.js 路径（由 home.nix 的 extraPackages 提供）
                copilot_node_command = "node",

                -- 行内建议（ghost text）
                suggestion = {
                  enabled = true,
                  auto_trigger = true,
                  -- nvim-cmp 菜单打开时自动隐藏 ghost text，避免两者重叠
                  hide_during_completion = true,
                  debounce = 75,
                  keymap = {
                    accept = "<M-l>",
                    accept_word = false,
                    accept_line = false,
                    next = "<M-]>",
                    prev = "<M-[>",
                    dismiss = "<C-]>",
                  },
                },

                -- 面板配置
                -- 关键修复：copilot.lua 默认会注册一个**全局 insert 模式**映射
                -- <M-CR> (Alt+Enter) 来打开面板。面板 buffer 是 modifiable=false
                -- 且会抢走焦点，所以在 Neovide 里一旦误触，之后每次输入都会得到
                -- "E21: Cannot make changes, 'modifiable' is off"。
                -- 在终端里 Alt+Enter 通常被拆成 <Esc><CR> 所以不会触发，
                -- GUI（Neovide）里才是真正的 <M-CR>，这就是只在 Neovide 复现的原因。
                -- 设为 false 关掉该全局映射；仍可用 :Copilot panel open 手动打开。
                panel = {
                  enabled = true,
                  auto_refresh = false,
                  keymap = {
                    jump_prev = "[[",
                    jump_next = "]]",
                    accept = "<CR>",
                    refresh = "gr",
                    open = false,
                  },
                },

                -- 文件类型配置
                filetypes = {
                  yaml = true,
                  markdown = true,
                  help = false,
                  gitcommit = false,
                  gitrebase = false,
                  hgcommit = false,
                  svn = false,
                  cvs = false,
                  ["."] = false,
                  nix = true,
                },
              })
            end,
          },
        }
      '';
    };

    "nvim/lua/plugins/formatting.lua" = {
      text = ''
        -- ============================================
        -- 代码格式化配置 (LSP 和 nil)
        -- ============================================

        return {
          {
            "neovim/nvim-lspconfig",
            event = { "BufReadPre", "BufNewFile" },
            config = function()
              local capabilities = vim.lsp.protocol.make_client_capabilities()
              capabilities = require("cmp_nvim_lsp").default_capabilities(capabilities)

              -- Nix Language Server (nil) - 使用新的 vim.lsp API
              local nil_cmd = { "nil" }
              
              -- 启动 nil_ls 服务器
              local function setup_nil()
                local root_dir = vim.fs.dirname(
                  vim.fs.find({ "flake.nix", ".git" }, { upward = true })[1]
                )
                
                local client_id = vim.lsp.start({
                  name = "nil",
                  cmd = nil_cmd,
                  root_dir = root_dir,
                  capabilities = capabilities,
                  settings = {
                    ["nil"] = {
                      formatting = {
                        command = { "nixfmt" },
                      },
                    },
                  },
                })
              end

              -- 为 nix 文件设置 LSP
              vim.api.nvim_create_autocmd("FileType", {
                pattern = "nix",
                callback = setup_nil,
              })

              -- 设置 LSP 快捷键和格式化
              vim.api.nvim_create_autocmd("LspAttach", {
                group = vim.api.nvim_create_augroup("UserLspConfig", { clear = true }),
                callback = function(ev)
                  local opts = { buffer = ev.buf }
                  vim.keymap.set("n", "gD", vim.lsp.buf.declaration, opts)
                  vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
                  vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
                  vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)
                  vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, opts)
                  vim.keymap.set("n", "<leader>f", function()
                    vim.lsp.buf.format({ async = true })
                  end, opts)
                end,
              })
            end,
            dependencies = {
              "nvim-cmp",
              "cmp-nvim-lsp",
            },
          },
        }
      '';
    };

    "nvim/lua/plugins/completion.lua" = {
      text = ''
        -- ============================================
        -- 自动补全配置 (nvim-cmp)
        -- ============================================

        return {
          {
            "hrsh7th/nvim-cmp",
            event = "InsertEnter",
            config = function()
              local cmp = require("cmp")

              cmp.setup({
                mapping = {
                  ["<C-b>"] = cmp.mapping(cmp.mapping.scroll_docs(-4), { "i", "c" }),
                  ["<C-f>"] = cmp.mapping(cmp.mapping.scroll_docs(4), { "i", "c" }),
                  ["<C-Space>"] = cmp.mapping(cmp.mapping.complete(), { "i", "c" }),
                  ["<C-e>"] = cmp.mapping({
                    i = cmp.mapping.abort(),
                    c = cmp.mapping.close(),
                  }),
                  ["<CR>"] = cmp.mapping.confirm({ select = true }),
                },
                sources = cmp.config.sources({
                  { name = "nvim_lsp", priority = 9 },
                  { name = "buffer", priority = 5 },
                  { name = "path", priority = 3 },
                }),
              })

              -- 命令行补全
              cmp.setup.cmdline(":", {
                sources = cmp.config.sources({
                  { name = "path" },
                }, {
                  { name = "cmdline" },
                }),
              })
            end,
            dependencies = {
              "hrsh7th/cmp-nvim-lsp",
              "hrsh7th/cmp-buffer",
              "hrsh7th/cmp-path",
              "hrsh7th/cmp-cmdline",
            },
          },
        }
      '';
    };

    "nvim/lua/plugins/init.lua" = {
      text = ''
        -- ============================================
        -- 插件规范说明 (由 lazy.nvim 导入)
        -- 此文件为命名约定，实际插件定义在其他文件中
        -- ============================================

        return {}
      '';
    };

    "nvim/lua/plugins/ui.lua" = {
      text = ''
        -- ============================================
        -- UI 和主题配置
        -- ============================================

        return {
          {
            "nvim-tree/nvim-web-devicons",
            lazy = true,
          },
          {
            "nvim-lualine/lualine.nvim",
            dependencies = { "nvim-web-devicons" },
            config = function()
              require("lualine").setup({
                options = {
                  theme = "gruvbox",
                  icons_enabled = true,
                },
                sections = {
                  lualine_a = { "mode" },
                  lualine_b = { "branch", "diff" },
                  lualine_c = { "filename" },
                  lualine_x = { "diagnostics", "encoding", "fileformat", "filetype" },
                  lualine_y = { "progress" },
                  lualine_z = { "location" },
                },
              })
            end,
          },
          {
            "ellisonleao/gruvbox.nvim",
            priority = 1000,
            config = function()
              vim.cmd("colorscheme gruvbox")
            end,
          },
        }
      '';
    };

    "nvim/lua/plugins/nix.lua" = {
      text = ''
        -- ============================================
        -- Nix 语言支持配置
        -- ============================================

        return {
          {
            "LnL7/vim-nix",
            ft = { "nix" },
          },
        }
      '';
    };

    "nvim/lua/plugins/claudecode.lua" = {
      text = ''
        -- ============================================
        -- Claude Code 集成 (claudecode.nvim)
        -- ============================================
        -- coder/claudecode.nvim 是纯 Lua 实现的 Claude Code IDE 协议客户端，
        -- 和 VSCode 扩展走的是同一套 WebSocket 协议，所以能拿到同样的能力：
        -- 选区上下文、@ 引用文件、编辑以 diff 形式送回 Neovim 供审阅。
        --
        -- 它是从 Neovim 内部 spawn `claude` 可执行文件的，因此 `claude` 必须在
        -- nvim 的 wrapper PATH 里 —— 见上面 programs.neovim.extraPackages。
        -- 不需要设 terminal_cmd，默认值 "claude" 正好能从 PATH 找到。

        return {
          {
            "coder/claudecode.nvim",
            dependencies = { "folke/snacks.nvim" },
            cmd = {
              "ClaudeCode",
              "ClaudeCodeFocus",
              "ClaudeCodeSelectModel",
              "ClaudeCodeAdd",
              "ClaudeCodeSend",
              "ClaudeCodeTreeAdd",
              "ClaudeCodeStatus",
              "ClaudeCodeStart",
              "ClaudeCodeStop",
              "ClaudeCodeOpen",
              "ClaudeCodeClose",
              "ClaudeCodeDiffAccept",
              "ClaudeCodeDiffDeny",
              "ClaudeCodeCloseAllDiffs",
            },
            opts = {
              -- 终端界面
              terminal = {
                split_side = "right",
                split_width_percentage = 0.35,
                provider = "snacks",
                auto_close = true,
                auto_insert = true,
              },
              -- Claude 提出的修改以 diff 形式打开，审阅后再决定收不收
              diff_opts = {
                layout = "vertical",
                open_in_new_tab = false,
              },
            },
            keys = {
              { "<leader>a", nil, desc = "AI / Claude Code" },
              { "<leader>ac", "<cmd>ClaudeCode<cr>", desc = "开关 Claude 面板" },
              { "<leader>af", "<cmd>ClaudeCodeFocus<cr>", desc = "聚焦 Claude 面板" },
              { "<leader>ar", "<cmd>ClaudeCode --resume<cr>", desc = "恢复历史会话" },
              { "<leader>aC", "<cmd>ClaudeCode --continue<cr>", desc = "继续上一次会话" },
              { "<leader>am", "<cmd>ClaudeCodeSelectModel<cr>", desc = "选择模型" },
              { "<leader>ab", "<cmd>ClaudeCodeAdd %<cr>", desc = "把当前文件加入上下文" },
              { "<leader>as", "<cmd>ClaudeCodeSend<cr>", mode = "v", desc = "把选区发给 Claude" },
              { "<leader>aa", "<cmd>ClaudeCodeDiffAccept<cr>", desc = "接受 diff" },
              { "<leader>ad", "<cmd>ClaudeCodeDiffDeny<cr>", desc = "拒绝 diff" },
              { "<leader>aS", "<cmd>ClaudeCodeStatus<cr>", desc = "查看连接状态" },
            },
          },
          {
            -- claudecode.nvim 的终端后端，同时提供 diff 用的浮窗
            "folke/snacks.nvim",
            priority = 1000,
            lazy = false,
            opts = {
              input = { enabled = true },
              picker = { enabled = true },
            },
          },
        }
      '';
    };
  };

  # ============================================
  # GitHub CLI 认证说明 (仅供参考，不自动执行)
  # ============================================
  # 在新机器上配置 Copilot 认证，执行以下命令之一：
  #
  # 方式 1: 使用 GitHub CLI 认证 (自动化方式)
  #   gh auth login
  #   gh extension install github/gh-copilot
  #   # 然后在 Neovim 中运行: :Copilot auth
  #
  # 方式 2: 使用 VSCode 认证 (跳过本步，直接用 VSCode 完成认证)
  #   如不需要 GitHub CLI，可在 modules/development.nix 中注释掉 github-cli 行
}
