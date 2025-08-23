{ config, lib, pkgs, ... }:

let
  cfg = config.my.roles.bug-tracker;
  port = 8038;
  anubisPort = 8045;
  anubisMetricsPort = 8046;

  # redmine_webhook requires an extra Ruby dependency which is not provided in
  # the default environment for the Redmine package.
  patchedRubyEnv = pkgs.bundlerEnv {
    name = "redmine-with-extra-deps-env-${pkgs.redmine.version}";
    ruby = pkgs.ruby;
    gemdir = ./extra-deps;
    gemfile = ./extra-deps/Gemfile.combined;
    lockfile = ./extra-deps/Gemfile.combined.lock;
  };
  redmine-with-extra-deps = pkgs.redmine.overrideAttrs (final: prev: {
    buildInputs = [
      patchedRubyEnv
      patchedRubyEnv.wrappedRuby
    ];

    # As of redmine 5.1.5, these are CVE-2024-54133 and GHSA-r95h-9x8f-r3f7.
    meta.knownVulnerabilities = [];
  });
in {
  options.my.roles.bug-tracker.enable = lib.mkEnableOption "bugs.dolphin-emu.org tracker";

  config = lib.mkIf cfg.enable {
    services.redmine = {
      enable = true;
      inherit port;

      package = redmine-with-extra-deps;

      database.type = "postgresql";

      settings.production.email_delivery = {
        delivery_method = ":sendmail";
        sendmail_settings = {
          location = "/run/wrappers/bin/sendmail";
        };
      };

      plugins = {
        redmine_webhook = pkgs.fetchFromGitHub {
          owner = "suer";
          repo = "redmine_webhook";
          rev = "5bc9a84a3bf3a5c51a1ddff498aa79c8ac64a1aa";
          hash = "sha256-fLd18gSmBtrcV9Mg8OU1auifSHYQwu4V8zH3sANBM5w=";
        };

        redmine_issue_templates = pkgs.fetchFromGitHub {
          owner = "agileware-jp";
          repo = "redmine_issue_templates";
          rev = "18b8b3195cbf43ae3f08ae60c3c3dc762eefe883";
          hash = "sha256-WyIL+2UYKg7KjVua7uvNnG9dM7neTJoDR5SqbH48KKo=";
        };
      };
    };

    # Disable NoNewPrivileges, as it prevents setuid/setgid bits from working.
    # The nullmailer sendmail wrappers needs those to write to /var/spool/nullmailer.
    systemd.services.redmine.serviceConfig.NoNewPrivileges = lib.mkForce false;

    # Limit the maximum memory usage.
    systemd.services.redmine.serviceConfig.MemoryMax = "4G";

    # Restart in case Redmine was killed due to reaching the memory limit.
    systemd.services.redmine.serviceConfig.Restart = "always";
    systemd.services.redmine.serviceConfig.RestartSec = 10;

    services.anubis.instances.redmine = {
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

          # Search engine crawlers to allow
          - import: (data)/crawlers/_allow-good.yaml

          # Allow common "keeping the internet working" routes (well-known, favicon, robots.txt)
          - import: (data)/common/keep-internet-working.yaml

          # Bots triggered by user-initiated actions
          - name: user-triggered-bots
            user_agent_regex: >-
              (?:ChatGPT-User|Claude-Web|OAI-SearchBot|Perplexity-User|Applebot)
            action: ALLOW

          # Generic catchall rule
          - name: generic-browser
            user_agent_regex: >-
              Mozilla|Opera
            action: CHALLENGE

          dnsbl: false

          status_codes:
            CHALLENGE: 200
            DENY: 200
        '';
      };
    };

    my.http.vhosts."bugs.dolphin-emu.org".proxyLocalPort = anubisPort;
  };
}
