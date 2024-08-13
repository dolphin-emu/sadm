builder:
{ config, lib, ... }:

let
  cfg = config.my.roles.foreign-builders;
  thisCfg = cfg."${builder.builderName}";
in {
  options.my.roles.foreign-builders."${builder.builderName}".enable = with lib; mkOption {
    description = "Guest builder for '${builder.builderName}'";
    type = types.bool;
    default = cfg.enable;
  };

  config = lib.mkIf thisCfg.enable {
    age.secrets.container-builder-env.file = ../../secrets/container-builder-env.age;
    age.secrets.oci-registry-password.file = ../../secrets/oci-registry-password.age;

    virtualisation.oci-containers.backend = "docker";

    virtualisation.oci-containers.containers."${builder.builderName}-builder" = {
      login = {
        registry = "oci-registry.dolphin-emu.org";
        username = "infra";
        passwordFile = config.age.secrets.oci-registry-password.path;
      };

      image = "oci-registry.dolphin-emu.org/${builder.containerImage}-builder:latest";

      environment = {
        BUILDBOT_HOST = "buildbot.dolphin-emu.org";
        WORKER_NAME = builder.builderName;
      };
      environmentFiles = [
        config.age.secrets.container-builder-env.path
      ];

      extraOptions = [
        "--device=/dev/kvm"
        "--cpus=4"
      ];
    };
  };
}
