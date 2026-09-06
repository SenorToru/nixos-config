{
  description = "Toru's Multi-Machine NixOS Systems";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nix-flatpak.url = "github:gmodena/nix-flatpak"; # 引入第三方模块
  };

  outputs =
    {
      self,
      nixpkgs,
      nix-flatpak,
      ...
    }@inputs:
    {
      nixosConfigurations = {
        # ThinkPad X1 Yoga 入口
        thinkpad = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            nix-flatpak.nixosModules.nix-flatpak # 启用模块扩展
            ./hosts/thinkpad/default.nix
          ];
        };

        # 将来华硕笔记本只需在此增加一个 asus 条目，引入 ./hosts/asus/default.nix
      };
    };
}
