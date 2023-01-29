{ config, lib, pkgs, ... }:

let
  cfg = config.my.roles.central;
  port = 8032;

  centralCfg = {
    web = {
      external_url = "https://central.dolphin-emu.org";
      bind = "127.0.0.1";
      inherit port;
    };

    irc = {
      server = "irc.libera.chat";
      port = 6667;
      ssl = false;
      nick = "irrawaddy";
      channels = [ "#dolphin-dev" ];
      rebuild_repo = "dolphin-emu/dolphin";
    };

    git = {
      repos_path = "/tmp/.central-repos";
      git_path = "${pkgs.git}/bin/git";
    };

    github = {
      account = {
        login = "dolphin-emu-bot";
        token = "!FileInclude ${config.age.secrets.gh-bot-token.path}";
      };

      maintain = [ "dolphin-emu/dolphin" ];
      notify = [
        "dolphin-emu/analytics-ingest"
        "dolphin-emu/central"
        "dolphin-emu/fifoci"
        "dolphin-emu/gcdsp-ida"
        "dolphin-emu/hwtests"
        "dolphin-emu/netplay-index"
        "dolphin-emu/redmine"
        "dolphin-emu/sadm"
        "dolphin-emu/www"
      ];

      trusted_users = {
        group = "dolphin-emu/trusted-developers";
        refresh_interval = 300;
      };
      core_users = {
        group = "dolphin-emu/core-developers";
        refresh_interval = 600;
      };

      hook_hmac_secret = "!FileInclude ${config.age.secrets.gh-hook-hmac.path}";
      oauth = {
        client_id = "!FileInclude ${config.age.secrets.gh-oauth-client-id.path}";
        client_secret = "!FileInclude ${config.age.secrets.gh-oauth-client-secret.path}";
      };

      rebuild_command = "@dolphin-emu-bot rebuild";
      allow_self_merge_command = "@dolphin-emu-bot allowmerge";
      disallow_self_merge_command = "@dolphin-emu-bot disallowmerge";
    };

    buildbot = {
      url = "https://dolphin.ci/";

      pr_builders = [
        "pr-android"
        "pr-deb-x64"
        "pr-deb-dbg-x64"
        "pr-osx-universal"
        "pr-steam-osx-universal"
        "pr-steam-runtime-x64"
        "pr-steam-win-x64"
        "pr-ubu-x64"
        "pr-win-x64"
        "pr-win-arm64"
        "pr-win-dbg-x64"
        "pr-freebsd-x64"
        "lint"
      ];

      fifoci_builders = [
        "pr-fifoci-ogl-lin-mesa"
        "pr-fifoci-ogl-lin-radeon"
        "pr-fifoci-uberogl-lin-radeon"
        "pr-fifoci-sw-lin-mesa"
        "pr-fifoci-mvk-osx-m1"
        "pr-fifoci-mtl-osx-m1"
      ];
    };

    fifoci.url = "https://fifo.ci";
  };

  # Convert "!FileInclude foo" to !FileInclude "foo". nixpkgs's YAML utils do
  # not have support for the YAML object constructor syntax.
  rawCfgFile = pkgs.writeText "central.raw" (lib.generators.toYAML {} centralCfg);
  cfgFile = pkgs.runCommand "central.yml" {} ''
    sed 's/"!FileInclude /!FileInclude "/g' ${rawCfgFile} > $out
  '';
in {
  options.my.roles.central.enable = lib.mkEnableOption "Dolphin Central server";

  config = lib.mkIf cfg.enable {
    age.secrets.gh-bot-token = {
      file = ../../secrets/gh-bot-token.age;
      owner = "central";
    };
    age.secrets.gh-hook-hmac = {
      file = ../../secrets/gh-hook-hmac.age;
      owner = "central";
    };
    age.secrets.gh-oauth-client-id = {
      file = ../../secrets/gh-oauth-client-id.age;
      owner = "central";
    };
    age.secrets.gh-oauth-client-secret = {
      file = ../../secrets/gh-oauth-client-secret.age;
      owner = "central";
    };

    systemd.services.central = {
      description = "Dolphin central server";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        User = "central";
        Group = "central";
        ExecStart = "${pkgs.central}/bin/central --config=${cfgFile}";
      };
    };

    my.http.vhosts."central.dolphin-emu.org".proxyLocalPort = port;

    users.users.central = {
      isSystemUser = true;
      group = "central";
    };
    users.groups.central = {};
  };
}
