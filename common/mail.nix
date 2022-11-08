{ config, ... }:

{
  age.secrets.infra-smtp-relay = {
    file = ../secrets/infra-smtp-relay.age;
    owner = config.services.nullmailer.user;
  };

  services.nullmailer = {
    enable = true;
    remotesFile = config.age.secrets.infra-smtp-relay.path;
    config = {
      me = "${config.networking.hostName}.${config.networking.domain}";
      adminaddr = "root@dolphin-emu.org";
    };
  };
}
