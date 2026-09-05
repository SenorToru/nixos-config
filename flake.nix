{
  description = "Toru's Multi-Machine NixOS Systems";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs =
    { self, nixpkgs, ... }@inputs:
    {
      nixosConfigurations = {
        # ThinkPad X1 Yoga 入口
        thinkpad = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./hosts/thinkpad/default.nix
          ];
        };

        # 将来华硕笔记本只需在此增加一个 asus 条目，引入 ./hosts/asus/default.nix
      };
    };
}
