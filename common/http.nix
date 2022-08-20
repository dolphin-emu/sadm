# Wrapper module to configure nginx and define virtual hosts in a higher level
# fashion: enforce standards on TLS usage, simplify the common case of "just
# proxy pass to a service running on this port", etc.

{ config, lib, ... }:

let
  cfg = config.my.http;

  selectVhostsByAttr = attr: lib.filterAttrs (n: v: v ? ${attr}) cfg.vhosts;
  mapVhostsByAttr = attr: fn: lib.mapAttrs fn (selectVhostsByAttr attr);

  redirectVhosts = mapVhostsByAttr "redirect" (n: vh: {
    forceSSL = true;
    enableACME = true;
    locations."/".return = "302 ${vh.redirect}";
  });

  localProxyVhosts = mapVhostsByAttr "proxyLocalPort" (n: vh: {
    forceSSL = true;
    enableACME = true;
    locations."/".proxyPass = "http://localhost:${toString vh.proxyLocalPort}";
  });
in {
  options.my.http.vhosts = with lib; mkOption {
    type = types.attrs;
    default = {};
  };

  config = {
    services.nginx = {
      enable = true;

      recommendedGzipSettings = true;
      recommendedOptimisation = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;

      virtualHosts =
        redirectVhosts //
        localProxyVhosts;
    };

    security.acme.acceptTerms = true;
    security.acme.defaults.email = "root@dolphin-emu.org";

    networking.firewall.allowedTCPPorts = [ 80 443 ];
  };
}
