{ config, lib, pkgs, ... }:

let
  cfg = config.my.roles.fifoci-frontend;
  pkg = pkgs.fifoci-frontend;
  port = 8041;
  anubisPort = 8043;
  anubisMetricsPort = 8044;

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

        ExecStart = "${pkg}/bin/gunicorn --workers 8 fifoci.frontend.wsgi";
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

    services.anubis.instances.fifoci-frontend = {
      settings = {
        TARGET = "http://localhost:${toString port}";
        BIND = "127.0.0.1:${toString anubisPort}";
        BIND_NETWORK = "tcp";
        METRICS_BIND = "127.0.0.1:${toString anubisMetricsPort}";
        METRICS_BIND_NETWORK = "tcp";
        POLICY_FNAME = pkgs.writeText "botPolicies.yaml"
        ''
          bots:
          # Pathological bots to deny
          - import: (data)/bots/_deny-pathological.yaml
          - import: (data)/bots/aggressive-brazilian-scrapers.yaml

          # Allow common "keeping the internet working" routes (well-known, favicon, robots.txt)
          - import: (data)/common/keep-internet-working.yaml

          # FifoCI API
          - name: api-dff
            path_regex: ^/dff
            action: ALLOW

          - name: api-media
            path_regex: ^/media/dff
            action: ALLOW

          - name: api-existing-images
            path_regex: ^/existing-images
            action: ALLOW

          - name: api-result-import
            path_regex: ^/result/import
            action: ALLOW

          # Generic catchall rule
          - name: generic-browser
            user_agent_regex: >-
              Mozilla|Opera
            action: CHALLENGE

          dnsbl: false

          # By default, send HTTP 200 back to clients that either get issued a challenge
          # or a denial. This seems weird, but this is load-bearing due to the fact that
          # the most aggressive scraper bots seem to really, really, want an HTTP 200 and
          # will stop sending requests once they get it.
          status_codes:
            CHALLENGE: 200
            DENY: 200
        '';
      };
    };

    users.users."${user}" = {
      inherit group;
      home = stateDir;
      isSystemUser = true;
    };

    users.groups."${group}".members = [ config.services.nginx.user ];

    my.http.vhosts."fifoci.dolphin-emu.org".redirect = "https://fifo.ci";
    my.http.vhosts."${domain}".cfg = {
      locations."/".proxyPass = "http://localhost:${toString anubisPort}";

      locations."/media/".alias = mediaDir + "/";
      locations."/media/".extraConfig = "expires 30d;";
      locations."/static/".alias = staticDir + "/";
      locations."/static/".extraConfig = "expires 30d;";

      extraConfig = "client_max_body_size 512M;";
    };
  };
}
