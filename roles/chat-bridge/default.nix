{ config, lib, pkgs, ... }:

let
  cfg = config.my.roles.chat-bridge;

  chatBridgeCfg = {
    irc = {
      server = "irc.libera.chat";
      port = 6697;
      ssl = true;
      nick = "clymene";
      sasl_username = "clymene";
      sasl_password = "!FileInclude ${config.age.secrets.chat-bridge-irc-sasl-password.path}";
      channel = "#dolphin-dev";
      ignore_users = [ "irrawaddy" ];
    };

    discord = {
      token = "!FileInclude ${config.age.secrets.chat-bridge-discord-token.path}";
      channel = 822820107788746812;
      ignore_users = [ 1320924779556900984 ];
    };
  };

  # Convert "!FileInclude foo" to !FileInclude "foo". nixpkgs's YAML utils do
  # not have support for the YAML object constructor syntax.
  rawCfgFile = pkgs.writeText "chat-bridge.raw" (lib.generators.toYAML {} chatBridgeCfg);
  cfgFile = pkgs.runCommand "chat-bridge.yml" {} ''
    sed 's/"!FileInclude /!FileInclude "/g' ${rawCfgFile} > $out
  '';
in {
  options.my.roles.chat-bridge.enable = lib.mkEnableOption "Dolphin Discord-IRC Bridge";

  config = lib.mkIf cfg.enable {
    age.secrets.chat-bridge-irc-sasl-password = {
      file = ../../secrets/chat-bridge-irc-sasl-password.age;
      owner = "chat-bridge";
    };
    age.secrets.chat-bridge-discord-token = {
      file = ../../secrets/chat-bridge-discord-token.age;
      owner = "chat-bridge";
    };

    systemd.services.chat-bridge = {
      description = "Dolphin Discord-IRC bridge";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        User = "chat-bridge";
        Group = "chat-bridge";
        ExecStart = "${pkgs.chat-bridge}/bin/chat-bridge --config=${cfgFile} --no_local_logging";
      };
    };

    users.users.chat-bridge = {
      isSystemUser = true;
      group = "chat-bridge";
    };
    users.groups.chat-bridge = {};
  };
}
