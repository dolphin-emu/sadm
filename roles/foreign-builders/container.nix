builderName:
{ config, lib, ... }:

let
  cfg = config.my.roles.foreign-builders;
  thisCfg = cfg."${builderName}";
in {
  options.my.roles.foreign-builders."${builderName}".enable = with lib; mkOption {
    description = "Guest builder for '${builderName}'";
    type = types.bool;
    default = cfg.enable;
  };

  config = lib.mkIf thisCfg.enable {
    age.secrets.container-builder-env.file = ../../secrets/container-builder-env.age;
    age.secrets.oci-registry-password.file = ../../secrets/oci-registry-password.age;

    virtualisation.oci-containers.backend = "docker";

    virtualisation.oci-containers.containers."${builderName}-builder" = {
      login = {
        registry = "oci-registry.dolphin-emu.org";
        username = "infra";
        passwordFile = config.age.secrets.oci-registry-password.path;
      };

      image = "oci-registry.dolphin-emu.org/${builderName}-builder:latest";

      environment = {
        BUILDBOT_HOST = "buildbot.dolphin-emu.org";
        WORKER_NAME = builderName;
      };
      environmentFiles = [
        config.age.secrets.container-builder-env.path
      ];
    };
  };
}
