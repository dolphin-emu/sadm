# Wrapper module to configure nginx and define virtual hosts in a higher level
# fashion: enforce standards on TLS usage, simplify the common case of "just
# proxy pass to a service running on this port", etc.

{ config, lib, pkgs, ... }:

let
  cfg = config.my.http;

  selectVhostsByAttr = attr: lib.filterAttrs (n: v: v ? ${attr}) cfg.vhosts;
  mapVhostsByAttr = attr: fn: lib.mapAttrs fn (selectVhostsByAttr attr);

  commonVhostAttrs = {
    forceSSL = true;
    enableACME = true;
  };

  redirectVhosts = mapVhostsByAttr "redirect" (n: vh: commonVhostAttrs // {
    locations."/".return = "302 ${vh.redirect}";
  });

  localProxyVhosts = mapVhostsByAttr "proxyLocalPort" (n: vh: commonVhostAttrs // {
    locations."/".proxyPass = "http://127.0.0.1:${toString vh.proxyLocalPort}";
    locations."/".extraConfig = "client_max_body_size 0;";
  });

  localDirVhosts = mapVhostsByAttr "root" (n: vh: commonVhostAttrs // {
    locations."/".root = vh.root;
    locations."/".extraConfig = "autoindex off;";
  });

  customCfgVhosts = mapVhostsByAttr "cfg" (n: vh: commonVhostAttrs // vh.cfg);

  mainVhosts =
    redirectVhosts //
    localProxyVhosts //
    localDirVhosts //
    customCfgVhosts;

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

  # Special vhosts that aren't collected from other modules.
  specialVhosts."localhost" = {
    listen = [
      { addr = "127.0.0.1"; port = 80; }
      { addr = "[::1]"; port = 80; }
    ];

    locations."/vts" = {
      extraConfig = ''
        vhost_traffic_status_display;
      '';
    };
  };

  allVhosts = specialVhosts // mainVhosts // (dolphinEmuNetRedirects mainVhosts);
in {
  options.my.http.vhosts = with lib; mkOption {
    type = types.attrs;
    default = {};
  };

  config = {
    services.nginx = {
      enable = true;
      additionalModules = [ pkgs.nginxModules.vts ];

      enableReload = true;

      eventsConfig = ''
        worker_connections 1024;
      '';

      appendConfig = ''
        worker_processes auto;
      '';

      recommendedGzipSettings = true;
      recommendedOptimisation = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;
      commonHttpConfig = ''
        vhost_traffic_status_zone;
      '';

      virtualHosts = allVhosts;
    };

    security.acme.acceptTerms = true;
    security.acme.defaults.email = "root@dolphin-emu.org";

    networking.firewall.allowedTCPPorts = [ 80 443 ];

    my.monitoring.targets.nginx = {
      targetLocalPort = 80;
      metricsPath = "/vts/format/prometheus";
    };
  };
}
