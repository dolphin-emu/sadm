{ config, lib, ... }:

let
  cfg = config.my.roles.foreign-builders;
  enabledContainers = lib.filterAttrs (_: container: container.enable) cfg.containers;
  workerPasswordSecretName = container: "container-${container.workerName}-env";
  workerPasswordSecrets = lib.mapAttrs' (_: container:
    let
      secretName = workerPasswordSecretName container;
    in
      lib.nameValuePair secretName {
        file = ../../secrets + "/${secretName}.age";
      }) enabledContainers;
in {
  options.my.roles.foreign-builders = {
    enable = lib.mkEnableOption "Guest builders for foreign operating systems";

    containers = lib.mkOption {
      description = "Foreign builder containers to run on this host";
      default = {};
      type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
        options = {
          enable = lib.mkEnableOption "the ${name} builder container" // {
            default = true;
          };

          image = lib.mkOption {
            description = "Image name in the Dolphin OCI registry";
            type = lib.types.str;
            default = "${name}-builder";
          };

          workerName = lib.mkOption {
            description = "Buildbot worker name used by the builder container";
            type = lib.types.str;
            default = name;
          };
        };
      }));
    };
  };

  config = lib.mkIf cfg.enable {
    age.secrets = workerPasswordSecrets // {
      oci-registry-password.file = ../../secrets/oci-registry-password.age;
    };

    virtualisation.oci-containers.backend = "docker";

    virtualisation.oci-containers.containers = lib.mapAttrs' (name: container:
      lib.nameValuePair "${name}-builder" {
        login = {
          registry = "oci-registry.dolphin-emu.org";
          username = "infra";
          passwordFile = config.age.secrets.oci-registry-password.path;
        };

        image = "oci-registry.dolphin-emu.org/${container.image}:latest";

        environment = {
          BUILDBOT_HOST = "buildbot.dolphin-emu.org";
          WORKER_NAME = container.workerName;
        };
        environmentFiles = [
          config.age.secrets.${workerPasswordSecretName container}.path
        ];

        extraOptions = [
          "--device=/dev/kvm"
          "--cpus=4"
          "--shm-size=256m"
        ];
      }) enabledContainers;
  };
}
