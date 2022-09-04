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

  mainVhosts =
    redirectVhosts //
    localProxyVhosts;

  # Add redirects for all dolphin-emu.net equivalents -> dolphin-emu.org.
  dolphinEmuOrgVhosts = lib.filterAttrs (n: v: lib.hasSuffix ".dolphin-emu.org" n);
  dolphinEmuOrgToNet = n: (lib.removeSuffix ".dolphin-emu.org" n) + ".dolphin-emu.net";
  dolphinEmuNetRedirects = vhosts: lib.mapAttrs' (n: v:
    lib.nameValuePair (dolphinEmuOrgToNet n) {
      forceSSL = true;
      enableACME = true;
      globalRedirect = n;
    }
  ) (dolphinEmuOrgVhosts vhosts);

  allVhosts = mainVhosts // (dolphinEmuNetRedirects mainVhosts);
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

      virtualHosts = allVhosts;
    };

    security.acme.acceptTerms = true;
    security.acme.defaults.email = "root@dolphin-emu.org";

    networking.firewall.allowedTCPPorts = [ 80 443 ];
  };
}
