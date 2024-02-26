{ scion }:
{
  systemd.services.scion-control = {
    description = "SCION Control Service";
    after = [ "network-online.target" "scion-dispatcher.service" ];
    wants = [ "scion-dispatcher.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      User = "scion";
      Group = "scion";
      Type = "simple";
      ExecStart = "${scion}/bin/scion-control --config ${./cs.toml}";
      Restart = "on-failure";
      BindPaths = [ "/dev/shm:/run/shm" ];
      RuntimeDirectoryMode = "777";
#      DynamicUser = true;

      #AmbientCapabilities = "CAP_NET_BIND_SERVICE";
      #CapabilityBoundingSet = "CAP_NET_BIND_SERVICE";

      StateDirectory = "scion-control";
    };
  };
}
