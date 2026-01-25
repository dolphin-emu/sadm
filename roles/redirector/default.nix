{ config, lib, pkgs, ... }:

let
  cfg = config.my.roles.redirector;
  port = 8033;

  pkg = pkgs.buildGoModule {
    pname = "dolp.in-redirector";
    version = "0.0.1";
    src = ./.;
    vendorHash = null;
  };
in {
  options.my.roles.redirector.enable = lib.mkEnableOption "dolp.in redirector";

  config = lib.mkIf cfg.enable {
    systemd.services.redirector = {
      description = "dolp.in redirector";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        DynamicUser = true;
        WorkingDirectory = "${pkg}";
        ExecStart = "${pkg}/bin/redirector";
      };
    };

    my.http.vhosts."dolp.in".proxyLocalPort = port;
  };
}
