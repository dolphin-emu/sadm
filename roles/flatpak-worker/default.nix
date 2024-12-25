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

  flatpakPython = pkgs.python3.withPackages (p: [
    pkgs.buildbot-worker
  ]);

  flatpakScripts = with pkgs; stdenv.mkDerivation {
    name = "flatpak-scripts";
    src = ./utils;

    propagatedBuildInputs = [ bash coreutils ];

    unpackPhase = "true";
    installPhase = ''
      mkdir $out $out/bin
      install -m755 $src/clean_cache.sh $out/bin
      patchShebangs $out/bin
    '';
  };

  flatpakEnvPackages = with pkgs; [
    bash
    flatpakScripts
    flatpak
    git
  ];
in {
  options.my.roles.flatpak-worker.enable = lib.mkEnableOption "Flatpak worker";

  config = lib.mkIf cfg.enable {
    age.secrets."flatpak-worker-env-${config.networking.hostName}".file = ../../secrets/flatpak-worker-env-${config.networking.hostName}.age;

    systemd.tmpfiles.rules = [
      "d '${homeDir}' 0750 ${user} ${group} - -"
    ];

    systemd.services.flatpak-worker = {
      description = "Flatpak Buildbot Worker";
      after = [ "network.target" "systemd-logind.service" ];
      wantedBy = [ "multi-user.target" ];
      path = flatpakEnvPackages;

      environment = {
        BUILDBOT_HOST = "buildbot.dolphin-emu.org";
        WORKER_NAME = "${config.networking.hostName}-flatpak";

        PYTHONPATH = "${flatpakPython}/${flatpakPython.sitePackages}";
      };

      preStart = ''
        mkdir -p ${workerDir}
        ${pkgs.rsync}/bin/rsync -a ${workerPackage}/ ${workerDir}/
        chmod u+w ${workerDir}

        flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

        flatpak install --user -y --noninteractive --or-update flathub org.flatpak.Builder  
        flatpak override --user --filesystem=home org.flatpak.Builder      
      '';

      serviceConfig = {
        Type = "simple";
        User = user;
        Group = group;
        WorkingDirectory = homeDir;
        EnvironmentFile = config.age.secrets."flatpak-worker-env-${config.networking.hostName}".path;
        ExecStart = "${pkgs.python3Packages.twisted}/bin/twistd --nodaemon --pidfile= --logfile=- --python ${workerDir}/buildbot.tac";
        Restart = "always";
        RestartSec = 10;
        Nice = 10;
        # We need to create a user session for this service.
        PAMName = "login";
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
