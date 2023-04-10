{ config, lib, pkgs, ... }:

let
  cfg = config.my.roles.buildbot;

  httpPort = 8010;
  pbPort = 9989;
  promPort = 8011;

  stateDir = "/var/lib/buildbot";

  buildbotScripts = pkgs.runCommand "buildbot-scripts" {} ''
    mkdir $out $out/bin $out/lib

    install -m755 ${./etc}/make_manifest.py $out/bin
    install -m755 ${./etc}/repack_dmg.sh $out/bin
    install -m755 ${./etc}/send_build.py $out/bin
    install -m755 ${./etc}/upload_to_steampipe.sh $out/bin

    install -m644 ${./etc}/buildbot.tac $out/lib
    install -m644 ${./etc}/master.cfg $out/lib
    install -m644 ${./etc}/steampipe_app_build.vdf $out/lib
  '';

  buildbotEnvPackages = with pkgs; [
    buildbotScripts

    (pkgs.python3.withPackages (p: [
      p.buildbot
      p.buildbot-plugins.console-view
      p.buildbot-plugins.grid-view
      p.buildbot-plugins.waterfall-view
      p.buildbot-plugins.www
      p.buildbot-worker

      (p.buildPythonPackage rec {
        pname = "buildbot-prometheus";
        version = "0c81a89bbe34628362652fbea416610e215b5d1e";

        src = pkgs.fetchFromGitHub {
          owner = "claws";
          repo = "buildbot-prometheus";
          rev = version;
          hash = "sha256-bz2Nv2RZ44i1VoPvQ/XjGMfTT6TmW6jhEVwItPk23SM=";
        };

        propagatedBuildInputs = [ p.buildbot p.prometheus-client p.twisted ];

        doCheck = false;
      })

      p.libarchive-c
      p.psycopg2
      p.pynacl
      p.requests
      p.txrequests
    ]))

    dmg2img
    p7zip
    steamcmd
  ];

  buildbotSecret = file: {
    inherit file;
    owner = "buildbot";
  };
in {
  options.my.roles.buildbot.enable = lib.mkEnableOption "buildbot master";

  config = lib.mkIf cfg.enable {
    age.secrets.buildbot-fifoci-frontend-api-key = buildbotSecret ../../secrets/fifoci-frontend-api-key.age;
    age.secrets.buildbot-gh-client-id = buildbotSecret ../../secrets/buildbot-gh-client-id.age;
    age.secrets.buildbot-gh-client-secret = buildbotSecret ../../secrets/buildbot-gh-client-secret.age;
    age.secrets.buildbot-workers-passwords = buildbotSecret ../../secrets/buildbot-workers-passwords.age;

    systemd.services.buildbot-master = {
      description = "Buildbot Master";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      path = buildbotEnvPackages;

      environment = {
        HTTP_PORT = toString httpPort;
        PB_PORT = toString pbPort;
        PROM_PORT = toString promPort;

        FIFOCI_FRONTEND_API_KEY_PATH = config.age.secrets.buildbot-fifoci-frontend-api-key.path;
        GH_CLIENT_ID_PATH = config.age.secrets.buildbot-gh-client-id.path;
        GH_CLIENT_SECRET_PATH = config.age.secrets.buildbot-gh-client-secret.path;
        WORKERS_PASSWORDS_PATH = config.age.secrets.buildbot-workers-passwords.path;
      };

      serviceConfig = {
        Type = "simple";
        User = "buildbot";
        Group = "buildbot";
        WorkingDirectory = stateDir;
        Restart = "always";
        RestartSec = 10;
      };

      preStart = ''
        ln -sf ${buildbotScripts}/lib/buildbot.tac .
        ln -sf ${buildbotScripts}/lib/master.cfg .

        buildbot upgrade-master

        rm buildbot.tac master.cfg
      '';

      script = ''
        exec twistd --nodaemon --pidfile= --logfile=- --python ${buildbotScripts}/lib/buildbot.tac
      '';
    };

    services.postgresql = {
      ensureDatabases = [ "buildbot" ];
      ensureUsers = [
        {
          name = "buildbot";
          ensurePermissions = {
            "DATABASE buildbot" = "ALL PRIVILEGES";
          };
        }
      ];
    };

    systemd.tmpfiles.rules = [
      "d '${stateDir}' 0750 buildbot buildbot - -"
    ];

    users.users.buildbot = {
      group = "buildbot";
      home = stateDir;
      isSystemUser = true;
    };

    users.groups.buildbot = {};

    my.http.vhosts."buildbot.dolphin-emu.org".redirect = "https://dolphin.ci";
    my.http.vhosts."new.dolphin.ci".cfg = {
      locations."/".proxyPass = "http://127.0.0.1:${toString httpPort}/";
      locations."/sse/" = {
        proxyPass = "http://127.0.0.1:${toString httpPort}/sse/";
        extraConfig = "proxy_buffering off;";
      };
      locations."/ws" = {
        proxyPass = "http://127.0.0.1:${toString httpPort}/ws";
        extraConfig = ''
          proxy_http_version 1.1;
          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection "upgrade";
          proxy_read_timeout 7200s;
        '';
      };
    };

    my.monitoring.targets.buildbot.targetLocalPort = promPort;
  };
}
