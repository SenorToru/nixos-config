{
  description = "Toru's Multi-Machine NixOS Systems";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nix-flatpak.url = "github:gmodena/nix-flatpak";

    # 原生 Zen Browser Flake 源
    zen-browser.url = "github:0xc000022070/zen-browser-flake";
  };

  outputs =
    {
      self,
      nixpkgs,
      nix-flatpak,
      zen-browser,
      ...
    }@inputs:
    {
      nixosConfigurations = {
        # ThinkPad X1 Yoga 入口
        thinkpad = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          # 将 inputs 透传进所有模块，以便在 desktop-gnome.nix 中直接取用
          specialArgs = { inherit inputs; };
          modules = [
            nix-flatpak.nixosModules.nix-flatpak
            ./hosts/thinkpad/default.nix
          ];
        };

        # 将来华硕笔记本只需在此增加一个 asus 条目，引入 ./hosts/asus/default.nix
      };
    };
}
