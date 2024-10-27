{ config, lib, pkgs, ... }:

let
  cfg = config.my.roles.nas-client;
in {
  options.my.roles.nas-client.enable = lib.mkEnableOption "NAS client";

  config = lib.mkIf cfg.enable {
    age.secrets.nas-credentials.file = ../../secrets/nas-credentials.age;
    age.secrets.nas-credentials-flatpak.file = ../../secrets/nas-credentials-flatpak.age;

    environment.systemPackages = [ pkgs.cifs-utils ];

    systemd.mounts = [
      {
        description = "Mount for /data/nas - artifacts storage";
        type = "cifs";
        what = "//u129977.your-storagebox.de/backup";
        where = "/data/nas";
        options = lib.strings.concatStringsSep "," [
          "rw"
          "uid=buildbot"
          "gid=nginx"
          "soft"
          "cache=none"
          "vers=default"
          "iocharset=utf8"
          "credentials=${config.age.secrets.nas-credentials.path}"
        ];
      }
      {
        description = "Mount for /data/flatpak - Flatpak repo storage";
        type = "cifs";
        what = "//u129977-sub2.your-storagebox.de/u129977-sub2";
        where = "/data/flatpak";
        options = lib.strings.concatStringsSep "," [
          "rw"
          "uid=flat-manager"
          "gid=nginx"
          "soft"
          "vers=default"
          "iocharset=utf8"
          "mfsymlinks"
          "cache=none"
          "credentials=${config.age.secrets.nas-credentials-flatpak.path}"
        ];
      }
    ];

    systemd.automounts = [
      {
        description = "Automount for /data/nas - artifacts storage";
        where = "/data/nas";
        wantedBy = [ "multi-user.target" ];
      }
      {
        description = "Automount for /data/flatpak - Flatpak repo storage";
        where = "/data/flatpak";
        wantedBy = [ "multi-user.target" ];
      }
    ];
  };
}
