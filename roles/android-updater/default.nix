{ config, lib, pkgs, ... }:

let
  cfg = config.my.roles.android-updater;

  pkg = with pkgs; stdenv.mkDerivation {
    name = "android-updater";
    src = ./updater.py;

    nativeBuildInputs = [ python3Packages.wrapPython ];
    propagatedBuildInputs = [ python3Packages.python ];
    pythonPath = with python3Packages; [
      httplib2
      google-api-python-client
      oauth2client
      requests
    ];

    unpackPhase = "true";
    installPhase = ''
      mkdir -p $out/bin
      cp $src $out/bin/android-updater
      patchShebangs $out/bin/android-updater
      chmod +x $out/bin/android-updater
    '';
    postFixup = "wrapPythonPrograms";
  };

  updaterService = { dolphinTrack, playstoreTrack }: {
    description = "Android Play Store updater (${dolphinTrack} -> ${playstoreTrack})";
    serviceConfig = {
      Type = "oneshot";
      DynamicUser = true;
      LoadCredential = "service-key-file:${config.age.secrets.androidpublisher-service-key.path}";
      ExecStart = ''
        ${pkg}/bin/android-updater \
          --package_name org.dolphinemu.dolphinemu \
          --playstore_track ${playstoreTrack} \
          --dolphin_track ${dolphinTrack} \
          --service_key_file ''${CREDENTIALS_DIRECTORY}/service-key-file
      '';
    };
  };
in {
  options.my.roles.android-updater.enable = lib.mkEnableOption "Android Play Store updater";

  config = lib.mkIf cfg.enable {
    age.secrets.androidpublisher-service-key.file = ../../secrets/androidpublisher-service-key.age;

    systemd.services.android-updater-release = updaterService {
      dolphinTrack = "beta";
      playstoreTrack = "production";
    };

    systemd.services.android-updater-dev = updaterService {
      dolphinTrack = "dev";
      playstoreTrack = "dev";
    };

    systemd.timers.android-updater-release = {
      description = "Android Play Store updater (release)";
      wantedBy = [ "timers.target" ];
      requires = [ "network-online.target" ];
      timerConfig = {
        OnCalendar = "*-*-* *:00:00";
        Persistent = true;
      };
    };

    systemd.timers.android-updater-dev = {
      description = "Android Play Store updater (dev)";
      wantedBy = [ "timers.target" ];
      requires = [ "network-online.target" ];
      timerConfig = {
        OnCalendar = "*-*-* *:30:00";
        Persistent = true;
      };
    };
  };
}
