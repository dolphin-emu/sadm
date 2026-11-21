{ config, lib, pkgs, ... }:

let
  cfg = config.my.roles.bug-tracker;
  port = 8038;
  anubisPort = 8045;
  anubisMetricsPort = 8046;

  ruby = pkgs.mkRuby {
    version = pkgs.mkRubyVersion "3" "4" "13" "";
    hash = "sha256-0NO/PdjCJKPDt+zYFqDxssvPT4e1r8vb6R0/7xd/NRo=";
    cargoHash = "sha256-5Tp8Kth0yO89/LIcU8K01z6DdZRr8MAA0DPKqDEjIt0=";
  };

  # redmine_webhook requires an extra Ruby dependency which is not provided in
  # the default environment for the Redmine package.
  patchedRubyEnv = pkgs.bundlerEnv {
    name = "redmine-with-extra-deps-env-${pkgs.redmine.version}";
    inherit ruby;
    gemdir = ./extra-deps;
    gemfile = ./extra-deps/Gemfile.combined;
    lockfile = ./extra-deps/Gemfile.combined.lock;

    # Taken from: https://github.com/NixOS/nixpkgs/blob/nixos-25.11/pkgs/by-name/re/redmine/package.nix#L32
    gemConfig = pkgs.defaultGemConfig // {
      trilogy = attrs: {
        buildInputs = [ pkgs.openssl ];
      };
      commonmarker = attrs: {
        cargoDeps = pkgs.rustPlatform.fetchCargoVendor {
          inherit (pkgs.buildRubyGem { inherit (attrs) gemName version source; })
            name
            src
            unpackPhase
            nativeBuildInputs
            ;
          hash = "sha256-rUNsf7DUVueD9revOR6Mab36XnVEmjL4bVv6TIMMqjM=";
        };
        dontBuild = false;
        nativeBuildInputs = [
          pkgs.cargo
          pkgs.rustc
          pkgs.rustPlatform.cargoSetupHook
          pkgs.rustPlatform.bindgenHook
        ];
        disallowedReferences = [
          pkgs.rustc.unwrapped
        ];
        preInstall = ''
          export CARGO_HOME="$PWD/../.cargo/"
        '';
        postInstall = ''
          find $out -type f -name .rustc_info.json -delete
        '';
      };
    };
  };
  redmine-with-extra-deps = (pkgs.redmine.override { ruby_3_4 = ruby; }).overrideAttrs (final: prev: {
    buildInputs = [
      patchedRubyEnv
      patchedRubyEnv.wrappedRuby
    ];
  });
in {
  options.my.roles.bug-tracker.enable = lib.mkEnableOption "bugs.dolphin-emu.org tracker";

  config = lib.mkIf cfg.enable {
    age.secrets.redmine-smtp-password = {
      file = ../../secrets/redmine-smtp-password.age;
      owner = "redmine";
    };

    services.redmine = {
      enable = true;
      inherit port;

      package = redmine-with-extra-deps;

      database.type = "postgresql";

      settings.production.email_delivery = {
        delivery_method = ":smtp";
        smtp_settings = {
          address = "smtp-dolphin-emu.alwaysdata.net";
          port = 587;
          domain = "dolphin-emu.org";
          user_name = "redmine@dolphin-emu.org";
          password = "<%= File.read('${config.age.secrets.redmine-smtp-password.path}').strip %>";
          authentication = ":plain";
          enable_starttls = true;
        };
      };

      plugins = {
        redmine_webhook = pkgs.fetchFromGitHub {
          owner = "dolphin-emu";
          repo = "redmine_webhook";
          rev = "5dd77474d8243b49ff7a7d0c42779f51cb839a79";
          hash = "sha256-yHUT+f+lGj8GplGZCZ+66HY47epSk88u1jIZ+6/zARA=";
        };

        redmine_issue_templates = pkgs.fetchFromGitHub {
          owner = "agileware-jp";
          repo = "redmine_issue_templates";
          rev = "18b8b3195cbf43ae3f08ae60c3c3dc762eefe883";
          hash = "sha256-WyIL+2UYKg7KjVua7uvNnG9dM7neTJoDR5SqbH48KKo=";
        };
      };
    };

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

          # Blocks all AI/LLM bots used for training or unknown/undocumented purposes.
          # Permits user agents with explicitly documented non-training use, and published IP allowlists.
          - import: (data)/meta/ai-block-moderate.yaml

          # Search engine crawlers to allow
          - import: (data)/crawlers/_allow-good.yaml

          # Allow common "keeping the internet working" routes (well-known, favicon, robots.txt)
          - import: (data)/common/keep-internet-working.yaml

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
