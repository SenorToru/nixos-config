{
  pkgs,
  inputs,
  ...
}:

let
  # Shared browser extension IDs
  protonPassExtId = "ghmbeldphafepmbegfdlkpapadhbakde";
  uBlockExtId = "cjpalhdlnbpafiamejdnhcphjbkeiagm";
  darkReaderExtId = "eimadpbcbfnmbkopoojfekhnkhdbieeh";
  sponsorBlockExtId = "mnjggcdmjocbbbhaepdhchncahnbgone";
  easyYoutubeExtId = "jipvbobkkjclnihgojbheifefgnfkhca";
  # LINE 官方的 Chrome 扩展（Chromium 系有官方版，Firefox / Zen 那边是第三方移植）
  lineExtId = "ophjlpahpchlmihnnnihgmmeilfjmjjc";

  # Zen browser package
  #
  # Zen 和 Firefox 一样靠企业策略（distribution/policies.json）装扩展。
  # 和 Firefox 那份（home/toru.nix 的 baseExtensionPolicies）是两份独立的清单 ——
  # Firefox 由 home-manager 的 programs.firefox 声明，Zen 是这里的系统包，
  # 两边加扩展要各加一次。
  #
  # **不能用 `.default.override { extraPolicies = ...; }`**，虽然 flake 的 README
  # 这么写。它的 zen-browser.nix 是 callPackage 出来的，外层 .override 改的是
  # callPackage 的参数（wrapFirefox / zen-browser-unwrapped），extraPolicies
  # 被当成多余参数静默丢掉 —— 构建成功、store 路径一字不变、policies.json
  # 仍是 {"policies":{}}。所以这里直接自己调 wrapFirefox。
  #
  # DisableAppUpdate 是 unwrapped 包本来就带的策略，但 wrapper 写的
  # policies.json 会盖掉它，所以在这里补回来。Nix 装的 Zen 本来也更新不了自己。
  zenPackage =
    pkgs.wrapFirefox
      inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.zen-browser-unwrapped
      {
        pname = "zen-browser";
        extraPolicies = {
          DisableAppUpdate = true;
          ExtensionSettings = {
            # LINE 的非官方 Firefox 移植版（作者 FoxRefire），说明见 home/toru.nix 同名条目
            "LINEPorted@FoxRefire" = {
              install_url = "https://addons.mozilla.org/firefox/downloads/latest/line-firefox-ported/latest.xpi";
              installation_mode = "force_installed";
            };
          };
        };
      };
in
{
  # System-level browser packages
  environment.systemPackages = with pkgs; [
    zenPackage
    brave
    # unfree，已由 common.nix 的 allowUnfree 放行
    google-chrome
  ];

  # Chromium configuration (applies to Brave, Chrome and other Chromium-based browsers)
  programs.chromium = {
    enable = true;
    extensions = [
      protonPassExtId
      uBlockExtId
      darkReaderExtId
      sponsorBlockExtId
      easyYoutubeExtId
      lineExtId
    ];
  };
}
