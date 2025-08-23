{ config, lib, pkgs, dolphin-emu, ... }:

let
  cfg = config.my.roles.traversal-server;
  port = 6262;  # UDP
  portAlt = 6226;  # UDP

  pkg = pkgs.dolphin-emu.overrideAttrs (final: prev: {
    pname = "traversal-server";

    version = "2503a";

    src = pkgs.fetchFromGitHub {
      owner = "dolphin-emu";
      repo = "dolphin";
      rev = "refs/tags/2503a";
      sha256 = "sha256-vhXiEgJO8sEv937Ed87LaS7289PLZlxQGFTZGFjs1So=";
      fetchSubmodules = true;
    };

    cmakeFlags = (prev.cmakeFlags or []) ++ [ "-DENABLE_QT=OFF" ];

    makeFlags = (prev.makeFlags or []) ++ [ "traversal_server" ];

    installPhase = ''
      mkdir -p $out/bin
      cp Binaries/traversal_server $out/bin/traversal-server
    '';

    patches = (lib.drop 1 prev.patches or []);

    preConfigure = "";
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

    networking.firewall.allowedUDPPorts = [ port portAlt ];
  };
}
