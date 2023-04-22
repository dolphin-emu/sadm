{ config, lib, pkgs, ... }:

{
  options = with lib; {
    my.monitoring.targets = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          # Mutually exclusive target specifications.
          targets = mkOption {
            type = types.nullOr (types.listOf types.str); 
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

          params = mkOption {
            type = types.attrsOf (types.listOf types.str);
            default = {};
          };

          relabelConfigs = mkOption {
            type = types.listOf(types.submodule {
              options = {
                sourceLabels = mkOption {
                  type = types.nullOr (types.listOf types.str);
                  default = null;
                };
                targetLabel = mkOption {
                  type = types.nullOr (types.str);
                  default = null;
                };
                replacement = mkOption {
                  type = types.nullOr (types.str);
                  default = null;
                };
              };
            });
            default = [];
          };
        };
      });
      default = {};
      description = lib.mdDoc "Monitoring targets to scrape for this service.";
    };

    my.monitoring.rules = mkOption {
      type = types.attrsOf types.lines;
      default = {};
      description = lib.mdDoc "Monitoring rules for this service.";
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

    my.monitoring.rules.node = ''
      groups:
      - name: alerts
        rules:
        - alert: JobDown
          expr: up == 0
          for: 5m
          annotations:
            summary: "Scraping target {{ $labels.down }} unreachable"

        - alert: UnitFailed
          expr: node_systemd_unit_state{state="failed"} == 1
          for: 5m
          annotations:
            summary: "systemd unit {{ $labels.name }} failed"

        - alert: LowDiskSpace
          expr: node_filesystem_free_bytes / node_filesystem_size_bytes < 0.15
          for: 30m
          annotations:
            summary: "Less than 15% disk space available on {{ $labels.mountpoint }}"
    '';

    services.prometheus.exporters.blackbox = {
      enable = true;
      port = 9102;
      configFile = pkgs.writeText "config.yaml"
        ''
          modules:
        '';
    };
  };
}
