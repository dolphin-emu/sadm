{ config, lib, pkgs, ... }:

let
  cfg = config.my.roles.monitoring;

  grafana-clickhouse-datasource = pkgs.callPackage ./grafana-clickhouse-datasource { };

  promPort = 8036;
  grafanaPort = 8037;
  alertmanagerPort = 8040;

  scrapeConfigs = lib.mapAttrsToList (job: opts: {
    job_name = job;
    scrape_interval = opts.scrapeInterval;
    scheme = opts.scheme;
    metrics_path = opts.metricsPath;
    static_configs = let
      target =
        if opts.target != null then
          opts.target
        else if opts.targetLocalPort != null then
          "localhost:${toString opts.targetLocalPort}"
        else
          throw "No target specification for monitoring service ${job}";
    in
      [{ targets = [ target ]; }];
  }) config.my.monitoring.targets;

  ruleFiles = lib.mapAttrsToList (job: rules:
    pkgs.writeText "prom-${job}.rules" rules
  ) config.my.monitoring.rules;

in {
  options.my.roles.monitoring.enable = lib.mkEnableOption "Monitoring infrastructure";

  config = lib.mkIf cfg.enable {
    services.prometheus = {
      enable = true;

      enableReload = true;

      listenAddress = "127.0.0.1";
      port = promPort;
      webExternalUrl = "https://prom.dolphin-emu.org/";

      inherit scrapeConfigs;
      inherit ruleFiles;

      alertmanager = {
        enable = true;

        listenAddress = "127.0.0.1";
        port = alertmanagerPort;
        webExternalUrl = "https://alerts.dolphin-emu.org";

        # Disable clustering binding to some random RFC1918 internal IP, we
        # don't use clustering anyway.
        extraFlags = [ "--cluster.listen-address=" ];

        configuration = {
          global = {
            smtp_smarthost = "127.0.0.1:25";
            smtp_from = "alerts@dolphin-emu.org";
            smtp_require_tls = false;
          };

          route = {
            receiver = "email";
          };

          receivers = [
            {
              name = "email";
              email_configs = [
                { to = "delroth+dolphin-alerts@gmail.com"; }
              ];
            }
          ];
        };
      };
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
          http_addr = "127.0.0.1";
          http_port = grafanaPort;
          domain = "mon.dolphin-emu.org";
          root_url = "https://mon.dolphin-emu.org/";
        };
      };

      declarativePlugins = [ grafana-clickhouse-datasource ];
    };

    my.http.vhosts."prom.dolphin-emu.org".proxyLocalPort = promPort;
    my.http.vhosts."mon.dolphin-emu.org".proxyLocalPort = grafanaPort;
    my.http.vhosts."alerts.dolphin-emu.org".proxyLocalPort = alertmanagerPort;
  };
}
