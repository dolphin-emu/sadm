{ config, lib, pkgs, ... }:

let
  cfg = config.my.roles.redirector;
  port = 8033;

  pkg = pkgs.runCommand "dolp.in-redirector" {} ''
    mkdir $out
    GOCACHE=$TMPDIR ${pkgs.go}/bin/go build -o $out/redirector ${./main.go}
    cp ${./README.md} $out/README.md
  '';
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
        ExecStart = "${pkg}/redirector";
      };
    };

    my.http.vhosts."dolp.in".proxyLocalPort = port;
  };
}
