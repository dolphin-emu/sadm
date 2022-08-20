{ config, lib, pkgs, ... }:

let
  cfg = config.my.roles.netplay-index;
  port = 8034;
in {
  options.my.roles.netplay-index.enable = lib.mkEnableOption "Netplay index server";

  config = lib.mkIf cfg.enable {
    age.secrets.geoip-license-key.file = ../../secrets/geoip-license-key.age;

    services.geoipupdate = {
      enable = true;
      settings = {
        AccountID = 756365;
        LicenseKey = config.age.secrets.geoip-license-key.path;
        EditionIDs = [ "GeoLite2-Country" ];
      };
    };

    systemd.services.netplay-index = {
      description = "Netplay index server";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      environment.GEOIP_DATABASE_PATH =
        "${config.services.geoipupdate.settings.DatabaseDirectory}/GeoLite2-Country.mmdb";

      serviceConfig = {
        Type = "simple";
        DynamicUser = true;
        StateDirectory = "netplay-index";
        WorkingDirectory = "/var/lib/netplay-index";
        ExecStart = "${pkgs.netplay-index}/bin/netplay-index --port=${toString port}";
      };
    };

    my.http.vhosts."lobby.dolphin-emu.org".proxyLocalPort = port;
  };
}
