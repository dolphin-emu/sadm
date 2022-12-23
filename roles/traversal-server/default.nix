{ config, lib, pkgs, dolphin-emu, ... }:

let
  cfg = config.my.roles.traversal-server;
  port = 6262;  # UDP

  pkg = pkgs.dolphin-emu-beta.overrideAttrs (final: prev: {
    pname = "traversal-server";

    makeFlags = (prev.makeFlags or []) ++ [ "traversal_server" ];

    installPhase = ''
      mkdir -p $out/bin
      cp Binaries/traversal_server $out/bin/traversal-server
    '';
  });
in {
  options.my.roles.traversal-server.enable = lib.mkEnableOption "Netplay Traversal server";

  config = lib.mkIf cfg.enable {
    systemd.services.traversal-server = {
      description = "Netplay Traversal server";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "notify";
        DynamicUser = true;
        ExecStart = "${pkg}/bin/traversal-server";
        Restart = "always";
        WatchdogSec = 10;
      };
    };

    networking.firewall.allowedUDPPorts = [ port ];
  };
}
