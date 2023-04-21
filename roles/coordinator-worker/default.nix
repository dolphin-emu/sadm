{ config, lib, pkgs, ... }:

let
  cfg = config.my.roles.coordinator-worker;
  user = "coordinator-worker";
  group = "coordinator-worker";

  homeDir = "/var/lib/coordinator-worker";
  workerDir = "${homeDir}/worker";

  workerPackage = pkgs.runCommand "coordinator-buildbot-worker" {} ''
    mkdir $out
    ${pkgs.python3Packages.buildbot-worker}/bin/buildbot-worker \
        create-worker \
        --relocatable \
        --force \
        $out BUILDBOT_HOST WORKER_NAME WORKER_PASSWORD

    sed -i "s/'BUILDBOT_HOST'/os.environ['BUILDBOT_HOST']/" $out/buildbot.tac
    sed -i "s/'WORKER_NAME'/os.environ.pop('WORKER_NAME')/" $out/buildbot.tac
    sed -i "s/'WORKER_PASSWORD'/os.environ.pop('WORKER_PASSWORD')/" $out/buildbot.tac

    echo "OatmealDome <julian@oatmealdome.me>" > $out/info/admin
    cat >$out/info/host <<EOF
    NixOS worker on ${config.networking.hostName}
    EOF
  '';

  coordinatorPython = pkgs.python3.withPackages (p: [
    p.buildbot-worker
  ]);

in {
  options.my.roles.coordinator-worker.enable = lib.mkEnableOption "Coordinator worker";

  config = lib.mkIf cfg.enable {
    age.secrets.container-builder-env.file = ../../secrets/container-builder-env.age;

    systemd.tmpfiles.rules = [
      "d '${homeDir}' 0750 ${user} ${group} - -"
    ];

    systemd.services.coordinator-worker = {
      description = "Coordinator Buildbot Worker";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        BUILDBOT_HOST = "buildbot.dolphin-emu.org";
        WORKER_NAME = "coordinator";

        PYTHONPATH = "${coordinatorPython}/${coordinatorPython.sitePackages}";
      };

      preStart = ''
        mkdir -p ${workerDir}
        ${pkgs.rsync}/bin/rsync -a ${workerPackage}/ ${workerDir}/
        chmod u+w ${workerDir}
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
    };
    users.groups."${group}" = {};
  };
}
