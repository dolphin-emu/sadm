{ config, lib, pkgs, ... }:

let
  cfg = config.my.roles.discord-bot;
in {
  options.my.roles.discord-bot.enable = lib.mkEnableOption "Discord bot";

  config = lib.mkIf cfg.enable {
    age.secrets.discord-bot-env.file = ../../secrets/discord-bot-env.age;

    systemd.services.discord-bot = {
      description = "Discord bot";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        DynamicUser = true;
        EnvironmentFile = config.age.secrets.discord-bot-env.path;
        ExecStart = "${pkgs.discord-bot}/bin/dolphinbot";
        Restart = "always";
        RestartSec = 10;
      };
    };
  };
}
