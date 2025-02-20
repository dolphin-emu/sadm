{ config, lib, pkgs, ... }:

let
  cfg = config.my.roles.buildbot;

  httpPort = 8010;
  pbPort = 9989;
  promPort = 8011;

  artifactsBaseDir = "/data/nas";
  stateDir = "/var/lib/buildbot";

  buildbotScripts = with pkgs; stdenv.mkDerivation {
    name = "buildbot-scripts";
    src = ./etc;

    nativeBuildInputs = [ python3Packages.wrapPython ];
    propagatedBuildInputs = [ bash python3Packages.python ];
    pythonPath = with python3Packages; [
      libarchive-c
      pynacl
      requests
    ];

    unpackPhase = "true";
    installPhase = ''
      mkdir $out $out/bin $out/lib

      install -m755 $src/make_manifest.py $out/bin
      install -m755 $src/send_build.py $out/bin

      install -m644 $src/buildbot.tac $out/lib
      install -m644 $src/flatpak_linter_exceptions.json $out/lib
      install -m644 $src/master.cfg $out/lib

      patchShebangs $out/bin
    '';
    postFixup = "wrapPythonPrograms";
  };

  buildbotEnvPackages = with pkgs; [
    buildbotScripts
  
    apksigner
    dmg2img
    openjdk
    openssh
    p7zip
  ];

  buildbotSecret = file: {
    inherit file;
    owner = "buildbot";
  };
in {
  options.my.roles.buildbot.enable = lib.mkEnableOption "buildbot master";

  config = lib.mkIf cfg.enable {
    age.secrets.android-keystore = buildbotSecret ../../secrets/android-keystore.age;
    age.secrets.android-keystore-pass = buildbotSecret ../../secrets/android-keystore-pass.age;
    age.secrets.buildbot-change-hook-credentials = buildbotSecret ../../secrets/buildbot-change-hook-credentials.age;
    age.secrets.buildbot-downloads-create-key = buildbotSecret ../../secrets/buildbot-downloads-create-key.age;
    age.secrets.buildbot-fifoci-frontend-api-key = buildbotSecret ../../secrets/fifoci-frontend-api-key.age;
    age.secrets.buildbot-flat-manager-worker-token = buildbotSecret ../../secrets/buildbot-flat-manager-worker-token.age;
    age.secrets.buildbot-gh-client-id = buildbotSecret ../../secrets/buildbot-gh-client-id.age;
    age.secrets.buildbot-gh-client-secret = buildbotSecret ../../secrets/buildbot-gh-client-secret.age;
    age.secrets.buildbot-steam-username = buildbotSecret ../../secrets/buildbot-steam-username.age;
    age.secrets.buildbot-steam-password = buildbotSecret ../../secrets/buildbot-steam-password.age;
    age.secrets.buildbot-workers-passwords = buildbotSecret ../../secrets/buildbot-workers-passwords.age;
    age.secrets.update-signing-key = buildbotSecret ../../secrets/update-signing-key.age;

    services.buildbot-master = {
      enable = true;
      masterCfg = "${buildbotScripts}/lib/master.cfg";
      home = stateDir;
      buildbotDir = stateDir;
      packages = buildbotEnvPackages;
      pythonPackages = p: [
        pkgs.buildbot-worker

        (p.buildPythonPackage rec {
          pname = "buildbot-prometheus";
          version = "0c81a89bbe34628362652fbea416610e215b5d1e";

          src = pkgs.fetchFromGitHub {
            owner = "claws";
            repo = "buildbot-prometheus";
            rev = version;
            hash = "sha256-bz2Nv2RZ44i1VoPvQ/XjGMfTT6TmW6jhEVwItPk23SM=";
          };

          propagatedBuildInputs = [ pkgs.buildbot p.prometheus-client p.twisted ];

          doCheck = false;
        })

        p.libarchive-c
        p.psycopg2
        p.pynacl
        p.requests
        p.txrequests
      ];
    };

    systemd.services.buildbot-master = {
      environment = {
        HTTP_PORT = toString httpPort;
        PB_PORT = toString pbPort;
        PROM_PORT = toString promPort;

        ARTIFACTS_BASE_DIR = artifactsBaseDir;

        ANDROID_KEYSTORE_PATH = config.age.secrets.android-keystore.path;
        ANDROID_KEYSTORE_PASS_PATH = config.age.secrets.android-keystore-pass.path;
        DOWNLOADS_CREATE_KEY_PATH = config.age.secrets.buildbot-downloads-create-key.path;
        FIFOCI_FRONTEND_API_KEY_PATH = config.age.secrets.buildbot-fifoci-frontend-api-key.path;
        FLAT_MANAGER_WORKER_TOKEN_PATH = config.age.secrets.buildbot-flat-manager-worker-token.path;
        CHANGE_HOOK_CREDENTIALS_PATH = config.age.secrets.buildbot-change-hook-credentials.path;
        GH_CLIENT_ID_PATH = config.age.secrets.buildbot-gh-client-id.path;
        GH_CLIENT_SECRET_PATH = config.age.secrets.buildbot-gh-client-secret.path;
        STEAM_ACCOUNT_USERNAME_PATH = config.age.secrets.buildbot-steam-username.path;
        STEAM_ACCOUNT_PASSWORD_PATH = config.age.secrets.buildbot-steam-password.path;
        UPDATE_SIGNING_KEY_PATH = config.age.secrets.update-signing-key.path;
        WORKERS_PASSWORDS_PATH = config.age.secrets.buildbot-workers-passwords.path;
        FLATPAK_LINTER_EXCEPTIONS_PATH = "${buildbotScripts}/lib/flatpak_linter_exceptions.json";
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
        ${pkgs.buildbot}/bin/buildbot upgrade-master
      '';
    };

    networking.firewall.allowedTCPPorts = [ pbPort ];

    services.postgresql = {
      ensureDatabases = [ "buildbot" ];
      ensureUsers = [
        {
          name = "buildbot";
          ensureDBOwnership = true;
        }
      ];
    };

    systemd.tmpfiles.rules = [
      "d '${stateDir}' 0750 buildbot buildbot - -"
    ];

    users.users.buildbot = {
      group = "buildbot";
      isNormalUser = lib.mkForce false;
      isSystemUser = true;
    };

    users.groups.buildbot = {};

    my.http.vhosts."buildbot.dolphin-emu.org".redirect = "https://dolphin.ci";
    my.http.vhosts."dolphin.ci".cfg = {
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
