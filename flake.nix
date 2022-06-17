{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-22.05";

  outputs = { self, nixpkgs }: {

    colmena = {
      meta.nixpkgs = import nixpkgs {
        system = "x86_64-linux";
      };
      "altair.dolphin-emu.org" = { pkgs, ... }: {
        # Let 'nixos-version --json' know about the Git revision
        # of this flake.
        system.configurationRevision = nixpkgs.lib.mkIf (self ? rev) self.rev;
        system.stateVersion = "22.05";

        boot.initrd.availableKernelModules = [ "nvme" ];
        fileSystems."/" = { fsType = "ext4"; device = "/dev/disk/by-label/root"; };

        boot.loader.grub = {
          enable = true;
          version = 2;
          efiSupport = false;
          devices = [ "/dev/nvme0n1" "/dev/nvme1n1" ];
        };

        networking.hostName = "altair";
        networking.domain = "dolphin-emu.org";
        networking.search = [ "dolphin-emu.org" ];

        networking.useDHCP = false;
        networking.interfaces.enp41s0 = {
          ipv4.addresses = [ { address = "144.76.17.114"; prefixLength = 27; } ];
          ipv6.addresses = [ { address = "2a01:4f8:191:44a::1"; prefixLength = 64; } ];
        };
        networking.defaultGateway = "144.76.17.97";
        networking.defaultGateway6 = { address = "fe80::1"; interface = "enp41s0"; };
        networking.nameservers = [ "8.8.8.8" ];

        services.openssh.enable = true;
        services.openssh.permitRootLogin = "prohibit-password";
        users.users.root.openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII3tjB4KYDok3KlWxdBp/yEmqhhmybd+w0VO4xUwLKKV" ];

        # Network configuration.
        networking.firewall.allowPing = true;
        networking.firewall.logRefusedConnections = false;
      };
    };
  };
}
