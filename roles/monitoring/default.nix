{ config, lib, pkgs, ... }:

let
  cfg = config.my.roles.monitoring;

  promPort = 8036;
  grafanaPort = 8037;
in {
  options.my.roles.monitoring.enable = lib.mkEnableOption "Monitoring infrastructure";

  config = lib.mkIf cfg.enable {
    services.prometheus = {
      enable = true;

      listenAddress = "127.0.0.1";
      port = promPort;
      webExternalUrl = "https://prom.dolphin-emu.org/";
    };

    services.grafana = {
      enable = true;
      port = grafanaPort;
      domain = "mon.dolphin-emu.org";
      rootUrl = "https://mon.dolphin-emu.org/";
    };

    my.http.vhosts."prom.dolphin-emu.org".proxyLocalPort = promPort;
    my.http.vhosts."mon.dolphin-emu.org".proxyLocalPort = grafanaPort;
  };
}
