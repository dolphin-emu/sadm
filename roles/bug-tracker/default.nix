{ config, lib, pkgs, ... }:

let
  cfg = config.my.roles.bug-tracker;
  port = 8038;

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

      settings.production.email_delivery.delivery_method = "sendmail";

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
          rev = "80c9ebfb4ab882a3c2c1072a364a8cfa29ec80d4";
          hash = "sha256-VHXed2P+Etq81UiQBzXA1FAXucYi1sm+xm2LIV+rshY=";
        };
      };
    };

    # Redmine strongly insists that sendmail should be at /usr/sbin/sendmail
    # and nowhere else.
    systemd.services.redmine.serviceConfig.BindPaths = let
      fakeSbin = pkgs.runCommand "fake-sbin" {} ''
        mkdir $out
        ln -s /run/wrappers/bin/sendmail $out/sendmail
      '';
    in [
      "${fakeSbin}:/usr/sbin"
    ];

    # Limit the maximum memory usage.
    systemd.services.redmine.serviceConfig.MemoryMax = "2G";

    # Restart in case Redmine was killed due to reaching the memory limit.
    systemd.services.redmine.serviceConfig.Restart = "always";
    systemd.services.redmine.serviceConfig.RestartSec = 10;

    my.http.vhosts."bugs.dolphin-emu.org".proxyLocalPort = port;
  };
}
