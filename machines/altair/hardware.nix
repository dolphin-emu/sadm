{
  boot.initrd.availableKernelModules = [ "nvme" ];
  fileSystems."/" = { fsType = "ext4"; device = "/dev/disk/by-label/root"; };

  boot.loader.grub = {
    enable = true;
    efiSupport = false;
    devices = [ "/dev/nvme0n1" "/dev/nvme1n1" ];
  };

  networking.useDHCP = false;
  networking.interfaces.enp41s0 = {
    ipv4.addresses = [ { address = "144.76.17.114"; prefixLength = 27; } ];
    ipv6.addresses = [ { address = "2a01:4f8:191:44a::1"; prefixLength = 64; } ];
  };
  networking.defaultGateway = "144.76.17.97";
  networking.defaultGateway6 = { address = "fe80::1"; interface = "enp41s0"; };
  networking.nameservers = [ "8.8.8.8" ];
}
