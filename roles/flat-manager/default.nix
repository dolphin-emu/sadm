{ config, lib, pkgs, ... }:

let
  cfg = config.my.roles.flat-manager;
  port = 8042;

  user = "flat-manager";
  group = "flat-manager";

  stateDir = "/var/lib/flat-manager";
  gpgDir = "${stateDir}/gpg";
  configPath = "${stateDir}/config.json";

  settings = {
    repos = let
      defineRepo = attrSet: {
        path = "/data/flatpak/${attrSet.name}";
        collection-id = "org.DolphinEmu.flatpak.${attrSet.name}";
        suggested-repo-name = attrSet.user-facing-name;
        runtime-repo-url = "https://dl.flathub.org/repo/flathub.flatpakrepo";
        gpg-key = "Dolphin Emulator Software Distribution";
        base-url = "https://flatpak.dolphin-emu.org/${attrSet.name}";
        subsets = {
          all = {
            collection-id = "org.DolphinEmu.flatpak.${attrSet.name}";
            base-url = "https://flatpak.dolphin-emu.org/${attrSet.name}";
          };
        };
      };
    in {
      dev = defineRepo {
        name = "dev";
        user-facing-name = "Dolphin Emulator (Dev)";
      };
      prs = defineRepo {
        name = "prs";
        user-facing-name = "Dolphin Emulator (PRs)";
      };
      releases = defineRepo {
        name = "releases";
        user-facing-name = "Dolphin Emulator (Releases)";
      };
    };

    port = port;
    delay-update-secs = 10;
    database-url = "postgresql://${user}@/flat-manager";
    # Some Flatpak operations on the build repo fail if it is stored in /data/flatpak.
    # I'm not sure why there are no problems when the other (non-build) repos are stored
    # there. While storing the build repo on the boot drive might degrade performance
    # according to the flat-manager documentation, I can't figure out how to fix the
    # underlying issue. ("flatpak build-commit-from" attempts to create a hard link
    # between two different repos, which succeeds, but attempting to open the new link
    # shortly after ends in EINVAL.)
    build-repo-base = "${stateDir}/build";
    build-gpg-key = "Dolphin Emulator Software Distribution";
    gpg-homedir = "${gpgDir}";
    base-url = "https://flat-manager.dolphin-emu.org";
    secret = "FLAT_MANAGER_SECRET";
  };

  settingsJson = pkgs.writeText "flat-manager-config.json" (lib.generators.toJSON {} settings);

  pkg = pkgs.rustPlatform.buildRustPackage rec {
    pname = "flat-manager";
    
    # Latest commit as of 10/27/2024.
    version = "7eb09a191918c09b767df86f5178760bc83135e6";

    src = pkgs.fetchFromGitHub {
      owner = "flatpak";
      repo = pname;
      rev = version;
      hash = "sha256-MGsxXY7PXUOTha+8lwr9HYdM4dDMA4wpqhbMleZPtX4=";
    };

    cargoHash = "sha256-n23A6e9cSGWbdukX4MiOvBkiaiZwZcO2wsrTeYrKqJo=";

    nativeBuildInputs = [ pkgs.pkg-config ];

    buildInputs = with pkgs; [
      openssl
      ostree
      glib
      postgresql
     ];
  };
in {
  options.my.roles.flat-manager.enable = lib.mkEnableOption "Flat Manager";

  config = lib.mkIf cfg.enable {
    age.secrets.flat-manager-repo-key = {
      file = ../../secrets/flat-manager-repo-key.age;
      owner = "flat-manager";
    };
    age.secrets.flat-manager-secret = {
      file = ../../secrets/flat-manager-secret.age;
      owner = "flat-manager";
    };

    systemd.tmpfiles.rules = [
      "d '${stateDir}' 0750 flat-manager flat-manager - -"
    ];

    systemd.services.flat-manager = {
      after = [ "network.target" "postgresql.service" ];
      requires = [ "postgresql.service" ];
      wantedBy = [ "multi-user.target" ];
      path = with pkgs; [
        flatpak
        gnupg
        jq
        ostree
      ];

      environment = {
        REPO_CONFIG = "${configPath}";
        RUST_BACKTRACE = "full";
      };

      serviceConfig = {
        Type = "simple";
        User = user;
        Group = group;
        WorkingDirectory = stateDir;
        ExecStart = "${pkg}/bin/flat-manager";
        Restart = "on-failure";
        RestartSec = 10;
      };

      preStart = ''
        rm -rf "${gpgDir}" || true
        mkdir -p "${gpgDir}"
        chmod 700 "${gpgDir}"

        gpg --homedir "${gpgDir}" --import "${config.age.secrets.flat-manager-repo-key.path}"

        FLAT_MANAGER_SECRET=$(cat "${config.age.secrets.flat-manager-secret.path}" | tr -d '\n')

        rm -f "${configPath}" || true
        jq --arg secret "$FLAT_MANAGER_SECRET" '.secret = $secret' "${settingsJson}" > "${configPath}"
      '';
    };

    services.postgresql = {
      ensureDatabases = [ "flat-manager" ];
      ensureUsers = [
        {
          name = user;
          ensureDBOwnership = true;
        }
      ];
    };

    users.users."${user}" = {
      group = group;
      home = stateDir;
      isSystemUser = true;
    };

    users.groups."${group}" = {};

    my.http.vhosts."flat-manager.dolphin-emu.org".proxyLocalPort = port;
    my.http.vhosts."flatpak.dolphin-emu.org".root = "/data/flatpak";
  };
}
