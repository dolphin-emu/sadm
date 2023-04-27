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
    params = opts.params;
    static_configs = let
      target_list =
        if opts.targets != null then
          opts.targets
        else if opts.targetLocalPort != null then
          [ "localhost:${toString opts.targetLocalPort}" ]
        else
          throw "No target specification for monitoring service ${job}";
    in
      [{ targets = target_list; }];
    relabel_configs = map (config: {
      source_labels = config.sourceLabels;
      target_label = config.targetLabel;
      replacement = config.replacement;
    }) opts.relabelConfigs;
  }) config.my.monitoring.targets;

  ruleFiles = lib.mapAttrsToList (job: rules:
    pkgs.writeText "prom-${job}.rules" rules
  ) config.my.monitoring.rules;

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
  options.my.roles.monitoring.enable = lib.mkEnableOption "Monitoring infrastructure";

  config = lib.mkIf cfg.enable {
    age.secrets.alerts-smtp-password.file = ../../secrets/alerts-smtp-password.age;

    age.secrets.grafana-admin-password = {
      file = ../../secrets/grafana-admin-password.age;
      owner = "grafana";
    };

    age.secrets.grafana-secret-key = {
      file = ../../secrets/grafana-secret-key.age;
      owner = "grafana";
    };

    services.prometheus = rec {
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

        environmentFile = config.age.secrets.alerts-smtp-password.path;

        # Disable clustering binding to some random RFC1918 internal IP, we
        # don't use clustering anyway.
        extraFlags = [ "--cluster.listen-address=" ];

        configuration = {
          global = {
            smtp_smarthost = "smtp-dolphin-emu.alwaysdata.net:25";
            smtp_from = "alerts@dolphin-emu.org";
            smtp_require_tls = true;
            smtp_auth_username = "alerts@dolphin-emu.org";
            smtp_auth_password = "$SMTP_PASSWORD";
          };

          route = {
            receiver = "email";
          };

          receivers = [
            {
              name = "email";
              email_configs = [
                { to = "admin@oatmealdome.me"; }
              ];
            }
          ];
        };
      };

      alertmanagers = [{
        static_configs = [{
          targets = [ "${alertmanager.listenAddress}:${toString alertmanager.port}" ];
        }];
      }];
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
