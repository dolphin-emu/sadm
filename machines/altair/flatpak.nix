{ pkgs, ... }:

{
  # Needed for Flatpak.
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config.common.default = "gtk";
  };

  services.flatpak.enable = true;
}
