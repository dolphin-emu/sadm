# Configuration relating to the hypervisor / container runtime and internal
# network used for CI builder guests.

{ pkgs, lib, ... }:

{
  security.polkit.enable = true;
  virtualisation.libvirtd.enable = true;

  networking.bridges.br-guests.interfaces = [];
  networking.interfaces.br-guests = {
    ipv4.addresses = [ { address = "172.16.42.254"; prefixLength = 24; } ];
    ipv6.addresses = [ { address = "2a01:4f8:191:44a:766d::1"; prefixLength = 80; } ];
  };

  networking.nat = {
    enable = true;
    internalInterfaces = [ "br-guests" ];
    externalInterface = "enp41s0";
  };

  boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = true;
  boot.kernel.sysctl."net.ipv6.conf.default.forwarding" = true;

  services.dnsmasq = {
    enable = true;
    resolveLocalQueries = false;
    extraConfig = ''
      port=0  # Disable DNS

      interface=br-guests
      bind-interfaces

      domain=builders.dolphin-emu.org

      dhcp-option=option:dns-server,8.8.8.8,8.8.4.4
      dhcp-option=option6:dns-server,2001:4860:4860::8888,2001:4860:4860::8844

      dhcp-range=172.16.42.0,static,12h
      dhcp-range=2a01:4f8:191:44a:766d::,2a01:4f8:191:44a:766d::ffff,static,80,12h
      dhcp-authoritative
      enable-ra

      dhcp-host=52:54:00:a1:e7:1c,172.16.42.10,win2022
      dhcp-host=52:54:00:a1:e7:1c,id:*,[2a01:4f8:191:44a:766d::10],win2022
    '';
  };
  networking.firewall.allowedUDPPorts = [ 67 547 ];

  systemd.services.guest-win2022 = {
    after = [ "libvirtd.service" ];
    requires = [ "libvirtd.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
    };

    script = ''
      ${pkgs.libvirt}/bin/virsh define ${./win2022.xml}
      ${pkgs.libvirt}/bin/virsh start win2022
    '';

    preStop = ''
      ${pkgs.libvirt}/bin/virsh shutdown win2022
      let "timeout = $(date +%s) + 20"
      while [ "$(${pkgs.libvirt}/bin/virsh list --name | grep --count '^win2022$')" -gt 0 ]; do
        if [ "$(date +%s)" -ge "$timeout" ]; then
          ${pkgs.libvirt}/bin/virsh destroy win2022
        else
          sleep 0.5
        fi
      done
    '';
  };
}
