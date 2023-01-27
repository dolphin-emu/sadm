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
  users.users.root.openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII3tjB4KYDok3KlWxdBp/yEmqhhmybd+w0VO4xUwLKKV" ];

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
    central.enable = true;
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
