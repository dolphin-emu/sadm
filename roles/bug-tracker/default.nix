{ config, lib, ... }:

let
  cfg = config.my.roles.bug-tracker;
  port = 8038;
in {
  options.my.roles.bug-tracker.enable = lib.mkEnableOption "bugs.dolphin-emu.org tracker";

  config = lib.mkIf cfg.enable {
    services.redmine = {
      enable = true;
      inherit port;

      database.type = "postgresql";
    };

    my.http.vhosts."bugs-new.dolphin-emu.org".proxyLocalPort = port;
  };
}
