{ config, lib, ... }:

let
  cfg = config.my.roles.foreign-builders;

  containerBuilders = [
    "debian"
    "steamrt"
    "ubuntu-lts"
  ];
in {
  options.my.roles.foreign-builders.enable =
    lib.mkEnableOption "Guest builders for foreign operating systems";

  imports = let
    containers = map
      (builderName: import ./container.nix builderName)
      containerBuilders;
  in (
    containers
  );

}
