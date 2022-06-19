{ self, pkgs, nixpkgs, ... }:

{
  imports = [
    ./hypervisor.nix
    ./hardware.nix
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

  system.stateVersion = "22.05";
  system.configurationRevision = pkgs.lib.mkIf (self ? rev) self.rev;
}
