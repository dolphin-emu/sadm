{ config, lib, ... }:

let
  cfg = config.my.roles.artifacts-mirror;
in {
  options.my.roles.artifacts-mirror.enable = lib.mkEnableOption "Artifacts serving / mirror";

  config = lib.mkIf cfg.enable {
    my.http.vhosts."dl.dolphin-emu.org".root = "/data/nas/dl";
    my.http.vhosts."update.dolphin-emu.org".root = "/data/nas/update";
  };
}
