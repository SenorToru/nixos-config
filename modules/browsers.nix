{
  config,
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
  ];

  # Chromium configuration (applies to Brave and other Chromium-based browsers)
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
