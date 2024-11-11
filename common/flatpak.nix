{ config, lib, pkgs, ... }:

let
  cfg = config.my.flatpak;
in {
  options.my.flatpak.enable = lib.mkEnableOption "Flatpak";

  config = lib.mkIf cfg.enable {
    # Needed for Flatpak.
    xdg.portal = {
      enable = true;
      extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
      config.common.default = "gtk";
    };

    services.flatpak.enable = true;
  };
}
