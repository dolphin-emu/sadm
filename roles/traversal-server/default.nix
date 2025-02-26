{ config, lib, pkgs, dolphin-emu, ... }:

let
  cfg = config.my.roles.traversal-server;
  port = 6262;  # UDP
  portAlt = 6226;  # UDP

  pkg = pkgs.dolphin-emu-beta.overrideAttrs (final: prev: {
    pname = "traversal-server";

    version = "2412";

    src = pkgs.fetchFromGitHub {
      owner = "dolphin-emu";
      repo = "dolphin";
      rev = "refs/tags/2412";
      sha256 = "sha256-5Eir8EQPGVSg2QXzzuHH9lf7CrV76KwmRsHiDqs6tD4=";
      fetchSubmodules = true;
    };

    cmakeFlags = (prev.cmakeFlags or []) ++ [ "-DENABLE_QT=OFF" ];

    makeFlags = (prev.makeFlags or []) ++ [ "traversal_server" ];

    # We need to use Dolphin-provided enet, as we use some features that haven't made it into a release yet.
    # Based on PR 12343 (https://github.com/dolphin-emu/dolphin/pull/12343/).
    postPatch = ''
      substituteInPlace CMakeLists.txt \
        --replace "libenet>=1.3.8" "libenet>=1.3.18"
    '';

    installPhase = ''
      mkdir -p $out/bin
      cp Binaries/traversal_server $out/bin/traversal-server
    '';

    patches = (lib.drop 1 prev.patches or []);
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
