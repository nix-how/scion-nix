{ scion }:
{
  users.users = {
    scion = {
      isSystemUser = true;
      group = "scion";
    };
  };
  users.groups = {
    scion = { };
  };
  systemd.services.scion-dispatcher = {
    description = "SCION Dispatcher";
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
#      User = "scion";
#      Group = "scion";
      Type = "simple";
      BindPaths = [ "/dev/shm:/run/shm" ];
      RuntimeDirectoryMode = "777";
      ExecStart = "${scion}/bin/scion-dispatcher --config ${./dispatcher.toml}";
#      ExecStartPre = "rm -rf /run/shm/dispatcher";
      Restart = "on-failure";
      DynamicUser = true;
      StateDirectory = "scion-dispatcher";
    };
  };

}
