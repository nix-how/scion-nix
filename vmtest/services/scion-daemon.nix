{ scion }:
{
  systemd.services.scion-daemon = {
    description = "SCION Daemon";
    wants = [ "scion-dispatcher.service" ];
    after = [ "network-online.target" "scion-dispatcher.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${scion}/bin/scion-daemon --config ${./sciond.toml}";
      Restart = "on-failure";
      DynamicUser = true;
      StateDirectory = "scion-daemon";
    };
  };

}
