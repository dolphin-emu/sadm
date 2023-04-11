{ config, lib, pkgs, ... }:

let
  cfg = config.my.roles.nas-client;
in {
  options.my.roles.nas-client.enable = lib.mkEnableOption "NAS client (for artifacts)";

  config = lib.mkIf cfg.enable {
    age.secrets.nas-credentials.file = ../../secrets/nas-credentials.age;

    environment.systemPackages = [ pkgs.cifs-utils ];

    systemd.mounts = [{
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
    }];

    systemd.automounts = [{
      description = "Automount for /data/nas - artifacts storage";
      where = "/data/nas";
      wantedBy = [ "multi-user.target" ];
    }];
  };
}
