{ config, lib, ... }:

let
  cfg = config.my.roles.foreign-builders;

  containerBuilders = [
    {
      builderName = "debian";
      containerImage = "debian";
    }
    {
      builderName = "steamrt";
      containerImage = "steamrt";
    }
    {
      builderName = "ubuntu-lts";
      containerImage = "ubuntu-lts";
    }
    {
      builderName = "android";
      containerImage = "ubuntu-lts";
    }
  ];
in {
  options.my.roles.foreign-builders.enable =
    lib.mkEnableOption "Guest builders for foreign operating systems";

  imports = let
    containers = map
      (builder: import ./container.nix builder)
      containerBuilders;
  in (
    containers
  );

}
