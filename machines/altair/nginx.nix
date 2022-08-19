{
  services.nginx = {
    enable = true;

    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedTlsSettings = true;

    virtualHosts = {
      "altair.dolphin-emu.org" = {
        forceSSL = true;
        enableACME = true;
        locations."/".return = "302 https://github.com/dolphin-emu/sadm";
      };
    };
  };

  security.acme.acceptTerms = true;
  security.acme.defaults.email = "root@dolphin-emu.org";

  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
