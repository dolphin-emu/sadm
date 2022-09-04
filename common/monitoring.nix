{
  services.prometheus.exporters.node = {
    enable = true;
    enabledCollectors = [ "interrupts" "systemd" "tcpstat" ];
    listenAddress = "127.0.0.1";
    port = 9101;
  };
}
