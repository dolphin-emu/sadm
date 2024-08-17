{ config, lib, pkgs, ... }:

let
  cfg = config.my.roles.fifoci-frontend;
  pkg = pkgs.fifoci-frontend;
  port = 8041;

  user = "fifoci-frontend";
  group = "fifoci-frontend";

  domain = "fifo.ci";

  stateDir = "/var/lib/fifoci-frontend";
  mediaDir = "${stateDir}/media";
  staticDir = "${stateDir}/static";

  fifociEnv = {
    DJANGO_SETTINGS_MODULE = "fifoci.frontend.settings.production";

    MEDIA_ROOT = mediaDir;
    STATIC_ROOT = staticDir;

    ALLOWED_HOSTS = domain;

    POSTGRES_DB = "fifoci";
    POSTGRES_USER = "fifoci-frontend";

    IMPORT_API_KEY_FILE = config.age.secrets.fifoci-frontend-api-key.path;
    SECRET_KEY_FILE = config.age.secrets.fifoci-frontend-secret-key.path;
  };
in {
  options.my.roles.fifoci-frontend.enable = lib.mkEnableOption "FifoCI frontend";

  config = lib.mkIf cfg.enable {
    age.secrets.fifoci-frontend-api-key = {
      file = ../../secrets/fifoci-frontend-api-key.age;
      owner = user;
    };
    age.secrets.fifoci-frontend-secret-key = {
      file = ../../secrets/fifoci-frontend-secret-key.age;
      owner = user;
    };

    systemd.tmpfiles.rules = [
      "d '${stateDir}' 0750 ${user} ${group} - -"
      "d '${mediaDir}' 0750 ${user} ${group} - -"
      "d '${staticDir}' 0750 ${user} ${group} - -"
    ];

    systemd.sockets.fifoci-frontend = {
      wantedBy = [ "sockets.target" ];
      listenStreams = [ "${toString port}" ];
    };

    systemd.services.fifoci-frontend = {
      after = [ "network.target" "postgresql.service" ];
      requires = [ "fifoci-frontend.socket" "postgresql.service" ];
      wantedBy = [ "multi-user.target" ];

      environment = fifociEnv;

      serviceConfig = {
        Type = "notify";
        User = user;
        Group = group;
        WorkingDirectory = stateDir;

        ExecStart = "${pkg.dependencyEnv}/bin/gunicorn --workers 8 fifoci.frontend.wsgi";
      };

      preStart = ''
        ${pkg}/bin/fifoci-frontend-manage collectstatic --noinput
        ${pkg}/bin/fifoci-frontend-manage migrate --noinput
      '';
    };

    # We can't use ensureDBOwnership because the database name doesn't match the database username.
    systemd.services.postgresql.postStart = lib.mkAfter ''
      $PSQL -tAc 'ALTER DATABASE "fifoci" OWNER TO "${user}";'
    '';

    services.postgresql = {
      ensureDatabases = [ "fifoci" ];
      ensureUsers = [
        {
          name = user;
        }
      ];
    };

    users.users."${user}" = {
      inherit group;
      home = stateDir;
      isSystemUser = true;
    };

    users.groups."${group}".members = [ config.services.nginx.user ];

    my.http.vhosts."fifoci.dolphin-emu.org".redirect = "https://fifo.ci";
    my.http.vhosts."${domain}".cfg = {
      locations."/".proxyPass = "http://localhost:${toString port}";

      locations."/media/".alias = mediaDir + "/";
      locations."/media/".extraConfig = "expires 30d;";
      locations."/static/".alias = staticDir + "/";
      locations."/static/".extraConfig = "expires 30d;";

      extraConfig = "client_max_body_size 512M;";
    };
  };
}
