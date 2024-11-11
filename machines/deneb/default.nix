{ self, pkgs, nixpkgs, ... }:

let
  my = import ../..;
in {
  imports = [
    my.modules

    ./hardware.nix
  ];

  services.openssh.enable = true;
  services.openssh.settings.PermitRootLogin = "prohibit-password";
  users.users.root.openssh.authorizedKeys.keys = [
    # degasus
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBfpcFMGpTNUUdmeMgNurPgj+mi2VBjFOcCQ3FcpDaO0"
    # MayImilae
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAibDWW0pesc3G7BGleBOVJbZpJIw1/CfB/SbBSsuo8l"
    # OatmealDome
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICAu/HTxWWR6vrEP2IgKy+sG9OT9B8/C+PE4d2U6b/Zz"
    # JosJuice
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIF+Q3PYfm5B/lLtRQBo7OR2Jdjv9TwBSJaOp8MrBB4uF"
  ];

  # Network configuration.
  networking.firewall.allowPing = true;
  networking.firewall.logRefusedConnections = false;

  networking.hostName = "deneb";
  networking.domain = "dolphin-emu.org";
  networking.search = [ "dolphin-emu.org" ];

  # Helpful administration tools.
  environment.systemPackages = with pkgs; [
    htop
  ];

  my.http.vhosts."deneb.dolphin-emu.org".redirect = "https://github.com/dolphin-emu/sadm";

  system.stateVersion = "24.05";
  system.configurationRevision = pkgs.lib.mkIf (self ? rev) self.rev;
}
