{ config, ... }:

{
  age.secrets.backup-passphrase.file = ../secrets/backup-passphrase.age;
  age.secrets.backup-ssh-key.file = ../secrets/backup-ssh-key.age;
  age.secrets.backup-ssh-known-hosts.file = ../secrets/backup-ssh-known-hosts.age;

  services.borgbackup.jobs.default = {
    repo = "ssh://u189211@u189211.your-storagebox.de:23/./dolphin";
    doInit = true;

    paths = [ "/data" "/var" ];
    exclude = [ "/data/nas" "/data/flatpak" ];

    compression = "auto,zstd";
    encryption = {
      mode = "repokey-blake2";
      passCommand = "cat ${config.age.secrets.backup-passphrase.path}";
    };

    environment = {
      BORG_RSH = "ssh -i ${config.age.secrets.backup-ssh-key.path} -o UserKnownHostsFile=${config.age.secrets.backup-ssh-known-hosts.path}";
    };

    startAt = "daily";
    prune.keep = {
      within = "1d";
      daily = 7;
      weekly = 4;
      monthly = 6;
    };
  };

  # Ignore warnings, e.g. "file has changed during backup".
  systemd.services.borgbackup-job-default.serviceConfig.SuccessExitStatus = "1";
}
