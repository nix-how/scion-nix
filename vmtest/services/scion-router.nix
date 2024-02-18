{ scion }:
{
  systemd.services.scion-router = {
    description = "SCION Router";
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${scion}/bin/scion-router --config ${./br.toml}";
      Restart = "on-failure";
      DynamicUser = true;
      StateDirectory = "scion-router";
    };
  };

}
