{
  description = "Toru's Multi-Machine NixOS Systems";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nix-flatpak.url = "github:gmodena/nix-flatpak"; # 为了试用services.flatpak.packages，引入第三方模块
  };

  outputs =
    {
      self,
      nixpkgs,
      nix-flatpak, # [A]必须先在函数列表中结构nix-flatpak
      ...
    }@inputs:
    {
      nixosConfigurations = {
        # ThinkPad X1 Yoga 入口
        thinkpad = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            nix-flatpak.nixosModules.nix-flatpak # [A]才能够在这里成功启用模块扩展
            ./hosts/thinkpad/default.nix
          ];
        };

        # 将来华硕笔记本只需在此增加一个 asus 条目，引入 ./hosts/asus/default.nix
      };
    };
}
