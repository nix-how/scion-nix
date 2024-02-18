{ scion }:
{
  systemd.services.scion-control = {
    description = "SCION Control Service";
    after = [ "network-online.target" "scion-dispatcher.service" ];
    wants = [ "scion-dispatcher.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${scion}/bin/scion-control --config ${./cs.toml}";
      Restart = "on-failure";
      DynamicUser = true;
      StateDirectory = "scion-control";
    };
  };
}
