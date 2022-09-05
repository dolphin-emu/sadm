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
in {
  options.my.roles.android-updater.enable = lib.mkEnableOption "Android Play Store updater";

  config = lib.mkIf cfg.enable {
    age.secrets.androidpublisher-service-key.file = ../../secrets/androidpublisher-service-key.age;

    systemd.services.android-updater = {
      description = "Android Play Store updater";
      serviceConfig = {
        Type = "oneshot";
        DynamicUser = true;
        LoadCredential = "service-key-file:${config.age.secrets.androidpublisher-service-key.path}";
        ExecStart = ''
          ${pkg}/bin/android-updater \
            --package_name org.dolphinemu.dolphinemu \
            --update_track beta \
            --service_key_file ''${CREDENTIALS_DIRECTORY}/service-key-file
        '';
      };
    };

    systemd.timers.android-updater = {
      description = "Android Play Store updater";
      wantedBy = [ "timers.target" ];
      requires = [ "network-online.target" ];
      timerConfig = {
        OnCalendar = "hourly";
        Persistent = true;
      };
    };
  };
}
