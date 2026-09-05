{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    vscode
    nil
    nixfmt
  ];
}
