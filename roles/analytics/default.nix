{ config, lib, pkgs, ... }:

let
  cfg = config.my.roles.analytics;
  port = 8035;

  pkg = pkgs.analytics-ingest;
in {
  options.my.roles.analytics.enable = lib.mkEnableOption "analytics ingest server";

  config = lib.mkIf cfg.enable {
    services.clickhouse.enable = true;

    # Restart in case of crashes, hangs, etc.
    systemd.services.clickhouse.serviceConfig.Restart = "always";
    systemd.services.clickhouse.serviceConfig.RestartSec = 3;

    systemd.sockets.analytics-ingest = {
      wantedBy = [ "sockets.target" ];
      listenStreams = [ "${toString port}" ];
    };

    systemd.services.analytics-ingest = {
      description = "Analytics ingest server";
      after = [ "network.target" ];
      requires = [ "analytics-ingest.socket" ];
      wants = [ "clickhouse.service" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        DASHBOARD_URL = "https://mon.dolphin-emu.org/d/000000003/analytics";
      };

      serviceConfig = {
        Type = "notify";
        DynamicUser = true;
        ExecStart = "${pkg.dependencyEnv}/bin/gunicorn analytics_ingest.__main__:app";

        # clickhouse does not properly use sd-notify to report successful
        # startup. In case we fail due to not being able to connect at startup,
        # retry a few times.
        Restart = "on-failure";
        RestartSec = 3;
      };
    };

    my.http.vhosts."analytics.dolphin-emu.org".proxyLocalPort = port;
    my.monitoring.targets.analytics-ingest.targetLocalPort = port;

    my.monitoring.rules.analytics-ingest = ''
      groups:
      - name: alerts
        rules:
        - alert: AbnormalIngestRate
          expr: rate(successful_ingests_total{job="analytics-ingest"}[5m]) < 1
          for: 5m
          annotations:
            summary: "Analytics ingest rate is abnormaly low (< 1 QPS over 5min)"
    '';
  };
}
