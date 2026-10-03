{
  config,
  lib,
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

  # ============================================
  # Firefox 系（Firefox / Zen）共用的扩展清单
  # ============================================
  # 键是扩展 ID（manifest 里的 gecko id），值是 AMO 上的 slug。
  # install_url 一律走 latest/<slug>/latest.xpi，首次安装就是最新版，
  # 之后靠 ExtensionUpdate 自动更新。查 ID 和 slug：
  #
  #   curl -fsSL https://addons.mozilla.org/api/v5/addons/addon/<slug>/ | jq .guid
  #
  # Firefox 由 home-manager 的 programs.firefox 声明（home/toru.nix），
  # Zen 是下面的系统包，两边隔着 NixOS / home-manager 的边界。
  # 所以清单放成 custom.firefoxPolicies 这个只读选项，home 侧用
  # osConfig.custom.firefoxPolicies 取 —— 和 custom.flakeHost 一样的办法。
  # **加扩展只改这里一处。**
  geckoExtensions = {
    "uBlock0@raymondhill.net" = "ublock-origin";
    "78272b6fa58f4a1abaac99321d503a20@proton.me" = "proton-pass";
    "addon@darkreader.org" = "darkreader";
    "sponsorBlocker@ajay.app" = "sponsorblock";
    # Easy Youtube Video Downloader Express
    "{b9acf540-acba-11e1-8ccb-001fd0e08bd4}" = "easy-youtube-video-download";
    # LINE 的 Chrome 扩展移植到 Firefox 的版本（非官方，作者 FoxRefire）。
    # LINE 官方只出 Chrome 扩展，Firefox 上只有这个。
    # 权限很宽：全部网站 + cookies，而且登录的是 LINE 账号 ——
    # 装它等于信任这个第三方作者，不是信任 LINE。
    "LINEPorted@FoxRefire" = "line-firefox-ported";
  };

  firefoxPolicies = {
    ExtensionUpdate = true;
    ExtensionSettings = {
      "*" = {
        installation_mode = "allowed";
      };
    }
    // lib.mapAttrs (_id: slug: {
      install_url = "https://addons.mozilla.org/firefox/downloads/latest/${slug}/latest.xpi";
      installation_mode = "force_installed";
    }) geckoExtensions;
  };

  # Zen browser package
  #
  # Zen 和 Firefox 一样靠企业策略（distribution/policies.json）装扩展。
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
        extraPolicies = config.custom.firefoxPolicies // {
          DisableAppUpdate = true;
        };
      };
in
{
  options.custom.firefoxPolicies = lib.mkOption {
    type = lib.types.attrs;
    readOnly = true;
    default = firefoxPolicies;
    description = "Firefox 与 Zen 共用的企业策略（扩展清单），home 侧经 osConfig 读取。";
  };

  config = {
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
  };
}
