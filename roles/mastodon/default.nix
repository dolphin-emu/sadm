{ config, lib, pkgs, ... }:

let
  cfg = config.my.roles.mastodon;
in {
  options.my.roles.mastodon.enable = lib.mkEnableOption "Mastodon server (social.dolphin-emu.org)";

  config = lib.mkIf cfg.enable {
    age.secrets.mastodon-smtp-password = {
      file = ../../secrets/mastodon-smtp-password.age;
      owner = config.services.mastodon.user;
    };

    services.mastodon = {
      enable = true;
      localDomain = "dolphin-emu.org";

      smtp.fromAddress = "social@dolphin-emu.org";
      smtp.host = "smtp-dolphin-emu.alwaysdata.net";
      smtp.user = "infra@dolphin-emu.org";
      smtp.passwordFile = config.age.secrets.mastodon-smtp-password.path;
      smtp.authenticate = true;

      extraConfig = {
        SINGLE_USER_MODE = "true";
        WEB_DOMAIN = "social.dolphin-emu.org";
      };
    };

    my.http.vhosts."social.dolphin-emu.org".cfg = {
      root = "${config.services.mastodon.package}/public/";
      locations."/system/".alias = "/var/lib/mastodon/public-system/";
      locations."/".tryFiles = "$uri @proxy";

      locations."@proxy".proxyPass = "http://unix:/run/mastodon-web/web.socket";
      locations."@proxy".proxyWebsockets = true;

      locations."/api/v1/streaming/".proxyPass = "http://unix:/run/mastodon-streaming/streaming.socket";
      locations."/api/v1/streaming/".proxyWebsockets = true;
    };

    users.groups.mastodon.members = [ config.services.nginx.user ];
  };
}
