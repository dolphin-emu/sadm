{ config, lib, ... }:

let
  cfg = config.my.roles.oci-registry;

  port = 8039;
in {
  options.my.roles.oci-registry.enable = lib.mkEnableOption "OCI containers registry";

  config = lib.mkIf cfg.enable {
    age.secrets.oci-registry-htpasswd = {
      file = ../../secrets/oci-registry-htpasswd.age;
      owner = config.systemd.services.docker-registry.serviceConfig.User;
    };

    services.dockerRegistry = {
      enable = true;
      inherit port;

      enableGarbageCollect = true;

      extraConfig = {
        auth.htpasswd = {
          realm = "basic-realm";
          path = config.age.secrets.oci-registry-htpasswd.path;
        };
      };
    };

    my.http.vhosts."oci-registry.dolphin-emu.org".proxyLocalPort = port;
  };
}
