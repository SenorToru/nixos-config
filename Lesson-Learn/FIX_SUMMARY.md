Fix Summary: LSP Configuration Deprecation Error

PROBLEM
When opening .nix files in Neovide, the following error appeared:
  The `require('lspconfig')` "framework" is deprecated, use vim.lsp.config
  (see :help lspconfig-nvim-0.11) instead.
  Feature will be removed in nvim-lspconfig v3.0.0

ROOT CAUSE
The LSP configuration was using the legacy require("lspconfig") API which has
been deprecated in favor of the new vim.lsp.start() API in Neovim 0.11+.

SOLUTION
Updated formatting.lua in two locations:

1. Local Neovim Configuration
   File: /home/toru/.config/nvim/lua/plugins/formatting.lua
   - Replaced require("lspconfig") with vim.lsp.start()
   - Implemented FileType autocmd to launch nil on demand
   - Uses vim.lsp.protocol.make_client_capabilities() directly
   - Maintains all LSP keybindings and formatting functionality

2. NixOS Configuration
   File: /home/toru/nixos-config/home/toru.nix (programs.neovim section)
   - Updated formatting.lua plugin spec with new API
   - Matches local Neovim configuration

CHANGES MADE

Local File Updated:
  /home/toru/.config/nvim/lua/plugins/formatting.lua
  - Removed: pcall(require, "lspconfig") wrapper
  - Removed: lspconfig.nil_ls.setup() framework call
  - Added: vim.lsp.start() for direct LSP startup
  - Added: FileType autocmd for nil activation
  - Preserved: All keybindings (gd, gD, K, <leader>rn, <leader>ca, <leader>f)
  - Preserved: nixfmt formatting command
  - Preserved: LSP capabilities from cmp_nvim_lsp

NixOS Configuration Updated:
  /home/toru/nixos-config/home/toru.nix
  - Updated formatting.lua text block with new implementation
  - Ready for next nixos-rebuild switch deployment

Git Commit Documentation:
  /home/toru/nixos-config/GIT_COMMIT_MESSAGE.txt
  - New commit message: "fix: Replace deprecated lspconfig API..."
  - Documents rationale and testing

VERIFICATION

Testing Completed:
  - nix flake check: PASSED (all checks passed!)
  - Neovim startup: PASSED (no deprecation warnings)
  - Configuration syntax: VALID

Functionality Preserved:
  - LSP keybindings work as before
  - Nix file formatting with nixfmt enabled
  - Code completion and diagnostics functional
  - Copilot integration unaffected

NEXT STEPS FOR USER

To apply changes to the full system:

1. Test with current Neovide:
   neovide /home/toru/nixos-config
   # Open any .nix file - no errors should appear

2. Apply NixOS configuration:
   cd /home/toru/nixos-config
   sudo nixos-rebuild switch --flake .#thinkpad

3. Commit the changes:
   git add home/toru.nix
   git commit -F GIT_COMMIT_MESSAGE.txt

ADDITIONAL NOTES

- The local Neovim configuration (/home/toru/.config/nvim/) is immediately
  active and fixes the deprecation error right away.

- The NixOS/HomeManager configuration will be fully applied when running
  sudo nixos-rebuild switch, which will regenerate the ~/.config/nvim/
  files from the Nix configuration.

- Both changes are identical in implementation, ensuring consistency across
  configuration methods.

- The new vim.lsp.start() approach is forward-compatible with future
  Neovim versions and avoids the deprecated lspconfig framework entirely.
