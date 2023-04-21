{ self, pkgs, nixpkgs, ... }:

let
  my = import ../..;
in {
  imports = [
    my.modules

    ./hypervisor.nix
    ./hardware.nix
    ./postgres.nix
  ];

  services.openssh.enable = true;
  services.openssh.permitRootLogin = "prohibit-password";
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

  networking.hostName = "altair";
  networking.domain = "dolphin-emu.org";
  networking.search = [ "dolphin-emu.org" ];

  my.roles = {
    analytics.enable = true;
    android-updater.enable = true;
    artifacts-mirror.enable = true;
    bug-tracker.enable = true;
    buildbot.enable = true;
    central.enable = true;
    coordinator-worker.enable = true;
    fifoci-frontend.enable = true;
    fifoci-worker.enable = true;
    foreign-builders.enable = true;
    mastodon.enable = true;
    monitoring.enable = true;
    nas-client.enable = true;
    netplay-index.enable = true;
    oci-registry.enable = true;
    redirector.enable = true;
    traversal-server.enable = true;
  };

  my.http.vhosts."altair.dolphin-emu.org".redirect = "https://github.com/dolphin-emu/sadm";

  system.stateVersion = "22.05";
  system.configurationRevision = pkgs.lib.mkIf (self ? rev) self.rev;
}
