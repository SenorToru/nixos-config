{
  description = "Toru's Multi-Machine NixOS Systems";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nix-flatpak.url = "github:gmodena/nix-flatpak";
    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # Stylix —— 全局配色框架，配置见 modules/stylix.nix。
    # 必须跟 release-26.05 这个发布分支，和上面的 nixpkgs / home-manager 对齐。
    # 跟 master 的话它是按 nixpkgs unstable 开发的，选项和这里 pin 的 26.05
    # 会错位，出问题时很难判断是配置写错还是版本不匹配。
    stylix.url = "github:danth/stylix/release-26.05";
    stylix.inputs.nixpkgs.follows = "nixpkgs";

    # Agent Skills 源。这些仓库不是 flake，只是一棵放着 SKILL.md 的源码树，
    # 所以 `flake = false`，当普通源码取用（见 home/agent-skills.nix）。
    #
    # 版本由 flake.lock 钉死 —— 这是「新机器 build 完立刻拿到一模一样的
    # skill」的全部理由，别为了「总是最新」把它改成不钉死的写法。
    # 更新用 `skills-update`（它内部跑 nix flake update，**不带 sudo**，见坑 5）。
    #
    # 再加一个 skill 源时：这里加一个 input，然后在 home/agent-skills.nix
    # 的 skillSources 表里加一条，两处都要改。
    matt-skills.url = "github:mattpocock/skills";
    matt-skills.flake = false;

    # 原生 Zen Browser Flake 源
    zen-browser.url = "github:youwen5/zen-browser-flake";
    # optional, but recommended if you closely follow NixOS unstable so it shares
    # system libraries, and improves startup time
    # NOTE: if you experience a build failure with Zen, the first thing to check is to remove this line!
    zen-browser.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      nix-flatpak,
      home-manager,
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
