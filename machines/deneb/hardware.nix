{
  boot.initrd.availableKernelModules = [ "xhci_pci" "virtio_scsi" "sr_mod" ];
  boot.initrd.kernelModules = [ "virtio_gpu" ];
  boot.kernelParams = [ "console=tty" ];

  fileSystems."/" = {
    fsType = "ext4";
    device = "/dev/disk/by-label/root";
  };
  fileSystems."/boot" = {
    fsType = "vfat";
    device = "/dev/disk/by-label/boot";
    options = [ "fmask=0007" "dmask=0007" ];
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.useDHCP = false;
  networking.interfaces.enp1s0 = {
    ipv4.addresses = [ { address = "49.12.191.172"; prefixLength = 32; } ];
    ipv6.addresses = [ { address = "2a01:4f8:c012:da67::1"; prefixLength = 64; } ];
  };
  networking.defaultGateway = { address = "172.31.1.1"; interface = "enp1s0"; };
  networking.defaultGateway6 = { address = "fe80::1"; interface = "enp1s0"; };
  networking.nameservers = [ "8.8.8.8" ];

  nixpkgs.hostPlatform.system = "aarch64-linux";
}
