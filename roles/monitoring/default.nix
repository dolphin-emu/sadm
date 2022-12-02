{ config, lib, pkgs, ... }:

let
  cfg = config.my.roles.monitoring;

  grafana-clickhouse-datasource = pkgs.callPackage ./grafana-clickhouse-datasource { };

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

      scrapeConfigs = [
        {
          job_name = "node";
          scrape_interval = "1m";
          scheme = "http";
          metrics_path = "/metrics";
          static_configs = [{ targets = [ "localhost:9101" ]; }];
        }

        {
          job_name = "nginx";
          scrape_interval = "1m";
          scheme = "http";
          metrics_path = "/vts/format/prometheus";
          static_configs = [{ targets = [ "localhost" ]; }];
        }

        {
          job_name = "netplay-index";
          scrape_interval = "1m";
          scheme = "https";
          metrics_path = "/metrics";
          static_configs = [{ targets = [ "lobby.dolphin-emu.org" ]; }];
        }
      ];
    };

    age.secrets.grafana-admin-password = {
      file = ../../secrets/grafana-admin-password.age;
      owner = "grafana";
    };

    age.secrets.grafana-secret-key = {
      file = ../../secrets/grafana-secret-key.age;
      owner = "grafana";
    };

    services.grafana = {
      enable = true;

      settings = {
        "auth.anonymous".enabled = true;
        security = {
          admin_user = "grafana";
          admin_password = "$__file{${config.age.secrets.grafana-admin-password.path}}";
          secret_key = "$__file{${config.age.secrets.grafana-secret-key.path}}";
        };
        server = {
          http_port = grafanaPort;
          domain = "mon.dolphin-emu.org";
          root_url = "https://mon.dolphin-emu.org/";
        };
      };

      declarativePlugins = [ grafana-clickhouse-datasource ];
    };

    # NixOS overly sandboxes Grafana, which breaks compatibility with certain
    # plugins that use native code. Fixed in NixOS > 22.05.
    systemd.services.grafana.serviceConfig.SystemCallFilter =
      lib.mkForce [ "@system-service" "~@privileged" ];

    my.http.vhosts."prom.dolphin-emu.org".proxyLocalPort = promPort;
    my.http.vhosts."mon.dolphin-emu.org".proxyLocalPort = grafanaPort;
  };
}
