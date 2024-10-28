{ config, lib, pkgs, ... }:

let
  cfg = config.my.roles.flatpak-worker;
  user = "flatpak-worker";
  group = "flatpak-worker";

  homeDir = "/var/lib/flatpak-worker";
  workerDir = "${homeDir}/worker";

  workerPackage = pkgs.runCommand "flatpak-buildbot-worker" {} ''
    mkdir $out
    ${pkgs.buildbot-worker}/bin/buildbot-worker \
        create-worker \
        --relocatable \
        --force \
        $out BUILDBOT_HOST WORKER_NAME WORKER_PASSWORD

    sed -i "s/'BUILDBOT_HOST'/os.environ['BUILDBOT_HOST']/" $out/buildbot.tac
    sed -i "s/'WORKER_NAME'/os.environ.pop('WORKER_NAME')/" $out/buildbot.tac
    sed -i "s/'WORKER_PASSWORD'/os.environ.pop('WORKER_PASSWORD')/" $out/buildbot.tac

    echo "OatmealDome <oatmeal@dolphin-emu.org>" > $out/info/admin
    cat >$out/info/host <<EOF
    NixOS Flatpak worker on ${config.networking.hostName}
    EOF
  '';

  flatManagerClientPackage = pkgs.stdenv.mkDerivation {
    name = "flat-manager-client";

    src = pkgs.fetchFromGitHub {
      owner = "flatpak";
      repo = "flat-manager";
      rev = "7eb09a191918c09b767df86f5178760bc83135e6";
      hash = "sha256-MGsxXY7PXUOTha+8lwr9HYdM4dDMA4wpqhbMleZPtX4=";
    };

    nativeBuildInputs = with pkgs; [
      gobject-introspection
      python3Packages.wrapPython
      wrapGAppsNoGuiHook
    ];
    propagatedBuildInputs = [ pkgs.python3Packages.python ];
    buildInputs = with pkgs; [
      ostree
    ];
    pythonPath = with pkgs.python3Packages; [
      aiohttp
      pygobject3
      tenacity
    ];

    installPhase = ''
      mkdir -p $out/bin
      cp $src/flat-manager-client $out/bin/flat-manager-client
      patchShebangs $out/bin/flat-manager-client
      chmod +x $out/bin/flat-manager-client
    '';
    postFixup = "wrapPythonPrograms";
  };

  flatpakPython = pkgs.python3.withPackages (p: [
    pkgs.buildbot-worker
  ]);

  flatpakEnvPackages = with pkgs; [
    appstream
    bash
    flatManagerClientPackage
    flatpak
    flatpak-builder
    gdk-pixbuf
    git
    gnutar
    gzip
    librsvg
    xz
  ];
in {
  options.my.roles.flatpak-worker.enable = lib.mkEnableOption "Flatpak worker";

  config = lib.mkIf cfg.enable {
    age.secrets.container-builder-env.file = ../../secrets/container-builder-env.age;

    systemd.tmpfiles.rules = [
      "d '${homeDir}' 0750 ${user} ${group} - -"
    ];

    systemd.services.flatpak-worker = {
      description = "Flatpak Buildbot Worker";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      path = flatpakEnvPackages;

      environment = {
        BUILDBOT_HOST = "buildbot.dolphin-emu.org";
        WORKER_NAME = "${config.networking.hostName}-flatpak";

        PYTHONPATH = "${flatpakPython}/${flatpakPython.sitePackages}";

        # We need this so that we can read SVG files using librsvg.
        GDK_PIXBUF_MODULE_FILE = "${pkgs.librsvg}/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache";
      };

      preStart = ''
        mkdir -p ${workerDir}
        ${pkgs.rsync}/bin/rsync -a ${workerPackage}/ ${workerDir}/
        chmod u+w ${workerDir}

        flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
      '';

      serviceConfig = {
        Type = "simple";
        User = user;
        Group = group;
        WorkingDirectory = homeDir;
        EnvironmentFile = config.age.secrets.container-builder-env.path;
        ExecStart = "${pkgs.python3Packages.twisted}/bin/twistd --nodaemon --pidfile= --logfile=- --python ${workerDir}/buildbot.tac";
        Restart = "always";
        RestartSec = 10;
        Nice = 10;
      };
    };

    users.users."${user}" = {
      inherit group;
      isSystemUser = true;
      home = homeDir;
      useDefaultShell = true;
      packages = flatpakEnvPackages;
    };
    users.groups."${group}" = {};
  };
}
