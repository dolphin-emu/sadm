{ config, lib, pkgs, ... }:

{
  options = with lib; {
    my.monitoring.targets = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          # Mutually exclusive target specifications.
          target = mkOption {
            type = types.nullOr types.str;
            default = null;
          };
          targetLocalPort = mkOption {
            type = types.nullOr types.port;
            default = null;
          };

          scrapeInterval = mkOption {
            type = types.str;
            default = "1m";
          };

          scheme = mkOption {
            type = types.str;
            default = "http";
          };

          metricsPath = mkOption {
            type = types.str;
            default = "/metrics";
          };
        };
      });
      default = {};
      description = lib.mdDoc "Monitoring targets to scrape for this service.";
    };
  };

  config = {
    services.prometheus.exporters.node = {
      enable = true;
      enabledCollectors = [ "interrupts" "systemd" "tcpstat" ];
      listenAddress = "127.0.0.1";
      port = 9101;
    };

    my.monitoring.targets.node.targetLocalPort = 9101;
  };
}
