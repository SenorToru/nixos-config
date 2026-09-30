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

  # Zen browser package
  zenPackage = inputs.zen-browser.packages."${pkgs.stdenv.hostPlatform.system}".default;
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
    ];
  };
}
