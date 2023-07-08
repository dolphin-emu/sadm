{ config, lib, pkgs, ... }:

let
  cfg = config.my.roles.fifoci-worker;
  user = "fifoci-worker";
  group = "fifoci-worker";

  homeDir = "/var/lib/fifoci-worker";
  workerDir = "${homeDir}/worker";

  # fifociShell is a shell with the environment required to build Dolphin.
  # Setting up a development environment with NixOS is tricky, since this
  # requires running package hooks to get e.g. the proper PKG_CONFIG_PATH and
  # more.
  fifociShell = let
    dol = pkgs.dolphinEmuMaster;
    inputAttrs = [
      "buildInputs"
      "nativeBuildInputs"
      "propagatedBuildInputs"
      "propagatedNativeBuildInputs"
    ];
    deps = lib.concatMapStringsSep "\n" (attr:
      let
        l = dol."${attr}";
        spaceSeparated = lib.concatMapStringsSep " " (drv: "${drv}") l;
      in
        "${attr}=\"${spaceSeparated}\""
    ) inputAttrs;
  in pkgs.runCommand "fifoci-shell" {
    passthru = {
      shellPath = "/bin/fifoci-shell";
    };
  } ''
    mkdir -p $out/bin $out/share

    cat > $out/bin/fifoci-shell <<EOF
    #! /bin/sh
    rc=$out/share/rcfile
    BASH_ENV=\$rc exec ${pkgs.bashInteractive}/bin/bash --rcfile \$rc "\$@"
    EOF
    chmod +x $out/bin/fifoci-shell

    # Lifted from the nix-shell implementation.
    export NIX_BUILD_TOP=/tmp
    export NIX_STORE=/nix/store
    export IN_NIX_SHELL=impure
    export NIX_ENFORCE_PURITY=0

    ${deps}

    source ${pkgs.stdenv}/setup

    unset SSL_CERT_FILE NIX_SSL_CERT_FILE HOME PWD TMP TMPDIR TEMPDIR TEMP

    ${pkgs.coreutils}/bin/env |
      ${pkgs.gnused}/bin/sed -r 's/^([^=]+)=(.*)$/export \1="\2"/'> $out/share/rcfile

    ${pkgs.gnused}/bin/sed -ri 's/^(export PATH=.*)"$/\1:$PATH"/' $out/share/rcfile
  '';

  workerPackage = pkgs.runCommand "fifoci-buildbot-worker" {} ''
    mkdir $out
    ${pkgs.buildbot-worker}/bin/buildbot-worker \
        create-worker \
        --relocatable \
        --force \
        $out BUILDBOT_HOST WORKER_NAME WORKER_PASSWORD

    sed -i "s/'BUILDBOT_HOST'/os.environ['BUILDBOT_HOST']/" $out/buildbot.tac
    sed -i "s/'WORKER_NAME'/os.environ.pop('WORKER_NAME')/" $out/buildbot.tac
    sed -i "s/'WORKER_PASSWORD'/os.environ.pop('WORKER_PASSWORD')/" $out/buildbot.tac

    echo "Pierre Bourdon <delroth@dolphin-emu.org>" > $out/info/admin
    cat >$out/info/host <<EOF
    NixOS FifoCI worker on ${config.networking.hostName}
    EOF
  '';

  fifociPython = pkgs.python3.withPackages (p: [
    pkgs.buildbot-worker
  ]);

  fifociEnvPackages = with pkgs; [
    bash ccache ffmpeg git imagemagick ninja poetry
  ];
in {
  options.my.roles.fifoci-worker.enable = lib.mkEnableOption "FifoCI worker";

  config = lib.mkIf cfg.enable {
    age.secrets.container-builder-env.file = ../../secrets/container-builder-env.age;

    hardware.opengl.enable = true;

    systemd.tmpfiles.rules = [
      "d '${homeDir}' 0750 ${user} ${group} - -"
      "d '${homeDir}/dff' 0750 ${user} ${group} - -"
    ];

    systemd.services.fifoci-worker = {
      description = "FifoCI Buildbot Worker";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      path = fifociEnvPackages;

      environment = {
        BUILDBOT_HOST = "buildbot.dolphin-emu.org";
        WORKER_NAME = "${config.networking.hostName}-fifoci";

        PYTHONPATH = "${fifociPython}/${fifociPython.sitePackages}";
      };

      preStart = ''
        mkdir -p ${workerDir}
        ${pkgs.rsync}/bin/rsync -a ${workerPackage}/ ${workerDir}/
        chmod u+w ${workerDir}

        if ! [ -d fifoci ]; then
          git clone https://github.com/dolphin-emu/fifoci
        fi

        # Clean up build directories since cmake can't figure out paths might
        # have changes when a new system is pushed.
        for d in ${workerDir}/*; do
          [ -d "$d/build" ] && rm -rf $d || true
        done
      '';

      serviceConfig = {
        Type = "simple";
        User = user;
        Group = group;
        WorkingDirectory = homeDir;
        EnvironmentFile = config.age.secrets.container-builder-env.path;
        ExecStart = "${fifociShell}/bin/fifoci-shell -c 'exec ${pkgs.python3Packages.twisted}/bin/twistd --nodaemon --pidfile= --logfile=- --python ${workerDir}/buildbot.tac'";
        Restart = "always";
        RestartSec = 10;
        Nice = 10;
      };
    };

    users.users."${user}" = {
      inherit group;
      extraGroups = [ "video" ];
      isSystemUser = true;
      home = homeDir;
      shell = fifociShell;
      packages = fifociEnvPackages;
    };
    users.groups."${group}" = {};
  };
}
