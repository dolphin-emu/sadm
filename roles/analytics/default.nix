{ config, lib, pkgs, ... }:

let
  cfg = config.my.roles.analytics;
  port = 8035;
in {
  options.my.roles.analytics.enable = lib.mkEnableOption "analytics ingest server";

  config = lib.mkIf cfg.enable {
    services.clickhouse.enable = true;

    my.http.vhosts."analytics-new.dolphin-emu.org".proxyLocalPort = port;
  };
}
