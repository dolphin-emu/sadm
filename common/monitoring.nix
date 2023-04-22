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

  config = let
    relabelConfigs = [
      {
        sourceLabels = [ "__address__" ];
        targetLabel = "__param_target";
      }
      {
        sourceLabels = [ "__param_target" ];
        targetLabel = "instance";
      }
      {
        targetLabel = "__address__";
        replacement = "localhost:9102";
      }
    ];
  in {
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
            http_2xx:
              prober: http
              timeout: 5s
              http:
                valid_http_versions:
                  - "HTTP/1.1"
                  - "HTTP/2.0"
                valid_status_codes: []
                method: GET
                follow_redirects: true
            http_403:
              prober: http
              timeout: 5s
              http:
                valid_http_versions:
                  - "HTTP/1.1"
                  - "HTTP/2.0"
                valid_status_codes: [ 403 ]
                method: GET
                follow_redirects: true
        '';
    };

    my.monitoring.targets.http-2xx = {
      metricsPath = "/probe";
      params = {
        module = [ "http_2xx" ];
      };
      targets = [
        # alwaysdata services
        "https://dolphin-emu.org"
        "https://wiki.dolphin-emu.org"
        "https://forums.dolphin-emu.org"
        "https://fakenus.dolphin-emu.org"
        "https://ip.dolphin-emu.org"
        "https://ovhproxy.dolphin-emu.org"
        "https://discord.dolphin-emu.org" # 302 found

        # altair services
        "https://analytics.dolphin-emu.org" # 301 moved permanently
        "https://bugs.dolphin-emu.org"
        "https://dolphin.ci"
        "https://central.dolphin-emu.org"
        "https://etherpad.dolphin-emu.org"
        "https://fifo.ci"
        "https://social.dolphin-emu.org"
        "https://oci-registry.dolphin-emu.org"
        "https://dolp.in"
      ];
      relabelConfigs = relabelConfigs;
    };

    my.monitoring.targets.http-403 = {
      metricsPath = "/probe";
      params = {
        module = [ "http_403" ];
      };
      targets = [
        # alwaysdata services
        "https://dl-mirror.dolphin-emu.org"

        # altair services
        "https://dl.dolphin-emu.org"
        "https://symbols.dolphin-emu.org"
        "https://update.dolphin-emu.org"
      ];
      relabelConfigs = relabelConfigs;
    };
  };
}
