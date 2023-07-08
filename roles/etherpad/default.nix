{ config, lib, pkgs, ... }:

let
  cfg = config.my.roles.etherpad;
  port = 8014;

  stateDir = "/var/lib/etherpad-lite";

  settings = {
    ip = "127.0.0.1";
    inherit port;

    title = "Dolphin Etherpad";

    dbType = "postgres";
    dbSettings = "socket:/run/postgresql";

    editOnly = true;

    trustProxy = true;

    users.admin = {
      is_admin = true;
      password = "$" + "{ETHERPAD_ADMIN_PASSWORD}";
    };

    ep_http_hook = {
      url = "https://dolphin-emu.org/blog/etherpad/event";
      hmac_key = "$" + "{ETHERPAD_HMAC_KEY}";
    };
  };

  settingsJson = pkgs.writeText "etherpad-settings.json" (lib.generators.toJSON {} settings);

  pkg = pkgs.buildNpmPackage rec {
    pname = "etherpad-lite";
    version = "1.8.18";

    src = pkgs.fetchFromGitHub {
      owner = "ether";
      repo = pname;
      rev = version;
      hash = "sha256-FziTdHmZ7DgWlSd7AhRdZioQNEPmiGZFHjc8pwnpKIo=";
    };

    patches = [ ./add-npm-deps.patch ];

    # Allow running with a state directory != package install directory.
    postPatch = ''
      substituteInPlace node/utils/AbsolutePaths.js \
        --replace "let etherpadRoot = null" "let etherpadRoot = require('process').cwd()"
    '';

    nativeBuildInputs = [ pkgs.python3 ];  # For GYP

    npmDepsHash = "sha256-fxUH3COLcCL1jlc0ms9zwWoxKuZ1oDKDaD76qHHeWMI=";

    npmFlags = [ "--legacy-peer-deps" ];

    sourceRoot = "source/src";

    dontNpmBuild = true;

    forceGitDeps = true;
  };

  plugins.ep_http_hook = pkgs.buildNpmPackage rec {
    pname = "ep_http_hook";
    version = "0f3d2a24e7aea751ff416a7c596138b6e174434d";

    src = pkgs.fetchFromGitHub {
      owner = "dolphin-emu";
      repo = pname;
      rev = version;
      hash = "sha256-AEa2MRWUzuWUr/hbm7BRLHO08R6AsIta8jhEKhBkMC8=";
    };

    npmDepsHash = "sha256-xfMDDfd5elFoPgluh1lnqO119qwkITC+5U8nVwltxZc=";

    npmFlags = [ "--legacy-peer-deps" ];

    dontNpmBuild = true;

    forceGitDeps = true;
  };
in {
  age.secrets.etherpad-apikey = {
    file = ../../secrets/etherpad-apikey.age;
    owner = "etherpad";
  };
  age.secrets.etherpad-sessionkey = {
    file = ../../secrets/etherpad-sessionkey.age;
    owner = "etherpad";
  };
  age.secrets.etherpad-passwords = {
    file = ../../secrets/etherpad-passwords.age;
    owner = "etherpad";
  };

  systemd.tmpfiles.rules = [
    "d '${stateDir}' 0750 etherpad etherpad - -"
    "d '${stateDir}/node_modules' 0750 etherpad etherpad - -"
    "d '${stateDir}/var' 0750 etherpad etherpad - -"
  ];

  systemd.services.etherpad-lite = {
    after = [ "network.target" "postgresql.service" ];
    requires = [ "postgresql.service" ];
    wantedBy = [ "multi-user.target" ];

    environment.NODE_ENV = "production";

    serviceConfig = {
      Type = "simple";
      User = "etherpad";
      Group = "etherpad";
      WorkingDirectory = stateDir;
    };

    preStart = ''
      ln -sfT ${pkg}/lib/node_modules/ep_etherpad-lite "${stateDir}/src"

      ln -sfT ${pkg}/lib/node_modules/ep_etherpad-lite "${stateDir}/node_modules/ep_etherpad-lite"
      ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList
            (name: value: ''
              rm -rf "${stateDir}"/node_modules/${name}
              cp -R ${value}/lib/node_modules/${name} "${stateDir}"/node_modules/${name}
              chmod u+w -R "${stateDir}"/node_modules/${name}
            '')
            plugins
        )}
      ln -sf ${settingsJson} "${stateDir}/settings.json"
      ln -sf ${config.age.secrets.etherpad-apikey.path} "${stateDir}/APIKEY.txt"
      ln -sf ${config.age.secrets.etherpad-sessionkey.path} "${stateDir}/SESSIONKEY.txt"
    '';

    script = ''
      source ${config.age.secrets.etherpad-passwords.path}
      export ETHERPAD_ADMIN_PASSWORD
      export ETHERPAD_HMAC_KEY

      exec ${pkg}/bin/etherpad-lite
    '';
  };

  services.postgresql = {
    ensureDatabases = [ "etherpad" ];
    ensureUsers = [
      {
        name = "etherpad";
        ensurePermissions = {
          "DATABASE etherpad" = "ALL PRIVILEGES";
        };
      }
    ];
  };

  users.users.etherpad = {
    group = "etherpad";
    home = stateDir;
    isSystemUser = true;
  };

  users.groups.etherpad = {};

  my.http.vhosts."etherpad.dolphin-emu.org".proxyLocalPort = port;
}
