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

  nix.nixPath = [ "nixpkgs=${nixpkgs}" ];

  # Network configuration.
  networking.firewall.allowPing = true;
  networking.firewall.logRefusedConnections = false;

  networking.hostName = "altair";
  networking.domain = "dolphin-emu.org";
  networking.search = [ "dolphin-emu.org" ];

  my.roles = {
    netplay-index.enable = true;
    redirector.enable = true;
  };

  my.http.vhosts."altair.dolphin-emu.org".redirect = "https://github.com/dolphin-emu/sadm";

  system.stateVersion = "22.05";
  system.configurationRevision = pkgs.lib.mkIf (self ? rev) self.rev;
}
