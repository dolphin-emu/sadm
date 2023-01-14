{ config, lib, pkgs, ... }:

let
  cfg = config.my.roles.analytics;
  port = 8035;
in {
  options.my.roles.analytics.enable = lib.mkEnableOption "analytics ingest server";

  config = lib.mkIf cfg.enable {
    services.clickhouse.enable = true;
    services.clickhouse.package = pkgs.clickhouse.overrideAttrs (final: prev: rec {
      version = "22.8.11.15";

      src = pkgs.fetchFromGitHub {
        owner = "clickhouse";
        repo = "clickhouse";
        rev = "v${version}-lts";
        fetchSubmodules = true;
        hash = "sha256-ZFS7RgeTV/eMSiI0o9WO1fHjRkPDNZs0Gm3w+blGsz0=";
      };
    });

    # Restart in case of crashes, hangs, etc.
    systemd.services.clickhouse.serviceConfig.Restart = "always";
    systemd.services.clickhouse.serviceConfig.RestartSec = 3;

    systemd.services.analytics-ingest = {
      description = "Analytics ingest server";
      after = [ "network.target" ];
      wants = [ "clickhouse.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        DynamicUser = true;
        ExecStart = "${pkgs.analytics-ingest}/bin/analytics-ingest --port=${toString port}";

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
