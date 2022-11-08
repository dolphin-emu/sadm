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
  });
in {
  options.my.roles.bug-tracker.enable = lib.mkEnableOption "bugs.dolphin-emu.org tracker";

  config = lib.mkIf cfg.enable {
    services.redmine = {
      enable = true;
      inherit port;

      package = redmine-with-extra-deps;

      database.type = "postgresql";

      plugins = {
        redmine_webhook = pkgs.fetchFromGitHub {
          owner = "suer";
          repo = "redmine_webhook";
          rev = "5bc9a84a3bf3a5c51a1ddff498aa79c8ac64a1aa";
          hash = "sha256-fLd18gSmBtrcV9Mg8OU1auifSHYQwu4V8zH3sANBM5w=";
        };
      };
    };

    my.http.vhosts."bugs-new.dolphin-emu.org".proxyLocalPort = port;
  };
}
