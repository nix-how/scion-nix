{ scion, nixosTest, runCommand, writeShellScript }:
let
  trust-root-configuration-keys = runCommand "generate-trc-keys.sh" {
    buildInputs = [
      scion
    ];
  } ''
    set -euo pipefail

    mkdir /tmp/tutorial-scion-certs && cd /tmp/tutorial-scion-certs
    mkdir AS{1..5}

    # Create voting and root keys and (self-signed) certificates for core ASes
    pushd AS1
    scion-pki certificate create --profile=sensitive-voting <(echo '{"isd_as": "42-ffaa:1:1", "common_name": "42-ffaa:1:1 sensitive voting cert"}') sensitive-voting.pem sensitive-voting.key
    scion-pki certificate create --profile=regular-voting <(echo '{"isd_as": "42-ffaa:1:1", "common_name": "42-ffaa:1:1 regular voting cert"}') regular-voting.pem regular-voting.key
    scion-pki certificate create --profile=cp-root <(echo '{"isd_as": "42-ffaa:1:1", "common_name": "42-ffaa:1:1 cp root cert"}') cp-root.pem cp-root.key
    popd

    pushd AS2
    scion-pki certificate create --profile=cp-root <(echo '{"isd_as": "42-ffaa:1:2", "common_name": "42-ffaa:1:2 cp root cert"}') cp-root.pem cp-root.key
    popd

    pushd AS3
    scion-pki certificate create --profile=sensitive-voting <(echo '{"isd_as": "42-ffaa:1:3", "common_name": "42-ffaa:1:3 sensitive voting cert"}') sensitive-voting.pem sensitive-voting.key
    scion-pki certificate create --profile=regular-voting <(echo '{"isd_as": "42-ffaa:1:3", "common_name": "42-ffaa:1:3 regular voting cert"}') regular-voting.pem regular-voting.key
    popd

    # Create the TRC
    mkdir tmp
    echo '
    isd = 42
    description = "Demo ISD 42"
    serial_version = 1
    base_version = 1
    voting_quorum = 2

    core_ases = ["ffaa:1:1", "ffaa:1:2", "ffaa:1:3"]
    authoritative_ases = ["ffaa:1:1", "ffaa:1:2", "ffaa:1:3"]
    cert_files = ["AS1/sensitive-voting.pem", "AS1/regular-voting.pem", "AS1/cp-root.pem", "AS2/cp-root.pem", "AS3/sensitive-voting.pem", "AS3/regular-voting.pem"]

    [validity]
    not_before = '$(date +%s)'
    validity = "365d"' \
    > trc-B1-S1-pld.tmpl

    scion-pki trc payload --out=tmp/ISD42-B1-S1.pld.der --template trc-B1-S1-pld.tmpl
    rm trc-B1-S1-pld.tmpl

    # Sign and bundle the TRC
    scion-pki trc sign tmp/ISD42-B1-S1.pld.der AS1/sensitive-voting.{pem,key} --out tmp/ISD42-B1-S1.AS1-sensitive.trc
    scion-pki trc sign tmp/ISD42-B1-S1.pld.der AS1/regular-voting.{pem,key} --out tmp/ISD42-B1-S1.AS1-regular.trc
    scion-pki trc sign tmp/ISD42-B1-S1.pld.der AS3/sensitive-voting.{pem,key} --out tmp/ISD42-B1-S1.AS3-sensitive.trc
    scion-pki trc sign tmp/ISD42-B1-S1.pld.der AS3/regular-voting.{pem,key} --out tmp/ISD42-B1-S1.AS3-regular.trc

    scion-pki trc combine tmp/ISD42-B1-S1.AS{1,3}-{sensitive,regular}.trc --payload tmp/ISD42-B1-S1.pld.der --out ISD42-B1-S1.trc
    rm tmp -r

    # Create CA key and certificate for issuing ASes
    pushd AS1
    scion-pki certificate create --profile=cp-ca <(echo '{"isd_as": "42-ffaa:1:1", "common_name": "42-ffaa:1:1 CA cert"}') cp-ca.pem cp-ca.key --ca cp-root.pem --ca-key cp-root.key
    popd
    pushd AS2
    scion-pki certificate create --profile=cp-ca <(echo '{"isd_as": "42-ffaa:1:2", "common_name": "42-ffaa:1:2 CA cert"}') cp-ca.pem cp-ca.key --ca cp-root.pem --ca-key cp-root.key
    popd

    # Create AS key and certificate chains
    scion-pki certificate create --profile=cp-as <(echo '{"isd_as": "42-ffaa:1:1", "common_name": "42-ffaa:1:1 AS cert"}') AS1/cp-as.pem AS1/cp-as.key --ca AS1/cp-ca.pem --ca-key AS1/cp-ca.key --bundle
    scion-pki certificate create --profile=cp-as <(echo '{"isd_as": "42-ffaa:1:2", "common_name": "42-ffaa:1:2 AS cert"}') AS2/cp-as.pem AS2/cp-as.key --ca AS2/cp-ca.pem --ca-key AS2/cp-ca.key --bundle
    scion-pki certificate create --profile=cp-as <(echo '{"isd_as": "42-ffaa:1:3", "common_name": "42-ffaa:1:3 AS cert"}') AS3/cp-as.pem AS3/cp-as.key --ca AS1/cp-ca.pem --ca-key AS1/cp-ca.key --bundle
    scion-pki certificate create --profile=cp-as <(echo '{"isd_as": "42-ffaa:1:4", "common_name": "42-ffaa:1:4 AS cert"}') AS4/cp-as.pem AS4/cp-as.key --ca AS1/cp-ca.pem --ca-key AS1/cp-ca.key --bundle
    scion-pki certificate create --profile=cp-as <(echo '{"isd_as": "42-ffaa:1:5", "common_name": "42-ffaa:1:5 AS cert"}') AS5/cp-as.pem AS5/cp-as.key --ca AS2/cp-ca.pem --ca-key AS2/cp-ca.key --bundle

    for i in {1..5}
    do
      mkdir -p $out/AS$i
      cp AS$i/cp-as.{key,pem} $out/AS$i
    done

    mv *.trc $out
  '';
  imports = hostId: [
    (import ./services/scion-daemon.nix { inherit scion; })
    (import ./services/scion-router.nix { inherit scion; })
    (import ./services/scion-control.nix { inherit scion; })
    (import ./services/scion-dispatcher.nix { inherit scion; })
    ({
      networking = {
        useNetworkd = true;
        useDHCP = false;
        firewall.enable = false;
      };
      systemd.network.networks."01-eth1" = {
        name = "eth1";
        networkConfig.Address = "192.168.1.${toString hostId}/24";
      };

      environment.etc."scion/topology.json".source = ./topology${toString hostId}.json;
      environment.etc."scion/crypto/as".source = trust-root-configuration-keys + "/AS${toString hostId}";
      environment.etc."scion/certs/ISD42-B1-S1.trc".source = trust-root-configuration-keys + "/ISD42-B1-S1.trc";
      environment.etc."scion/keys/master0.key".text = "U${toString hostId}v4k23ZXjGDwDofg/Eevw==";
      environment.etc."scion/keys/master1.key".text = "dBMko${toString hostId}qMS8DfrN/zP2OUdA==";
      environment.systemPackages = [
        (builtins.trace trust-root-configuration-keys.outPath trust-root-configuration-keys)
        scion
      ];

    })
  ];
in
nixosTest {
  name = "scion-test";
  nodes = {
    scion01 = { ... }: {
      imports = (imports 1);
    };
    scion02 = { ... }: {
      imports = (imports 2);
    };
    scion03 = { ... }: {
      imports = (imports 3);
    };
    scion04 = { ... }: {
      imports = (imports 4);
    };
    scion05 = { ... }: {
      imports = (imports 5);
    };
#    scion03 = { ... }: {
#      inherit imports;
#      environment.etc."scion/topology.json".source = ./topology3.json;
#      environment.etc."scion/crypto/as".source = trust-root-configuration-keys + "/AS3";
#      environment.etc."scion/certs/ISD42-B1-S1.trc".source = trust-root-configuration-keys + "/ISD42-B1-S1.trc";
#      environment.etc."scion/keys/master0.key".text = "U5v4k23ZXjGDwDofg/Eevw==";
#      environment.etc."scion/keys/master1.key".text = "dPMko3qMS8DfrN/zP2OUdA==";
#      environment.systemPackages = [
#        (builtins.trace trust-root-configuration-keys.outPath trust-root-configuration-keys)
#        scion
#      ];
#    };
#    scion04 = { ... }: {
#      inherit imports;
#      environment.etc."scion/topology.json".source = ./topology4.json;
#      environment.etc."scion/crypto/as".source = trust-root-configuration-keys + "/AS4";
#      environment.etc."scion/certs/ISD42-B1-S1.trc".source = trust-root-configuration-keys + "/ISD42-B1-S1.trc";
#      environment.etc."scion/keys/master0.key".text = "U5v4k23ZXjGDwDofg/Eevw==";
#      environment.etc."scion/keys/master1.key".text = "dPMko3qMS8DfrN/zP2OUdA==";
#      environment.systemPackages = [
#        (builtins.trace trust-root-configuration-keys.outPath trust-root-configuration-keys)
#        scion
#      ];
#    };
#    scion05 = { ... }: {
#      inherit imports;
#      environment.etc."scion/topology.json".source = ./topology5.json;
#      environment.etc."scion/crypto/as".source = trust-root-configuration-keys + "/AS5";
#      environment.etc."scion/certs/ISD42-B1-S1.trc".source = trust-root-configuration-keys + "/ISD42-B1-S1.trc";
#      environment.etc."scion/keys/master0.key".text = "U5v4k23ZXjGDwDofg/Eevw==";
#      environment.etc."scion/keys/master1.key".text = "dPMko3qMS8DfrN/zP2OUdA==";
#      environment.systemPackages = [
#        (builtins.trace trust-root-configuration-keys.outPath trust-root-configuration-keys)
#        scion
#      ];
#    };
  };
  testScript = let
    pingAll = writeShellScript "ping-all-scion.sh" ''

      ## This would be the dumb version of the smart loop below, but the smart
      ## loop uses crazy bash syntax, I should find a simpler way

      # scion showpaths 42-ffaa:1:1 --dispatcher /dev/shm/dispatcher/default.sock
      # scion showpaths 42-ffaa:1:2 --dispatcher /dev/shm/dispatcher/default.sock
      # scion showpaths 42-ffaa:1:3 --dispatcher /dev/shm/dispatcher/default.sock
      # scion showpaths 42-ffaa:1:4 --dispatcher /dev/shm/dispatcher/default.sock
      # scion showpaths 42-ffaa:1:5 --dispatcher /dev/shm/dispatcher/default.sock
      # scion ping 42-ffaa:1:1,192.168.1.1 -c 3 --dispatcher /dev/shm/dispatcher/default.sock
      # scion ping 42-ffaa:1:2,192.168.1.2 -c 3 --dispatcher /dev/shm/dispatcher/default.sock
      # scion ping 42-ffaa:1:3,192.168.1.3 -c 3 --dispatcher /dev/shm/dispatcher/default.sock
      # scion ping 42-ffaa:1:4,192.168.1.4 -c 3 --dispatcher /dev/shm/dispatcher/default.sock
      # scion ping 42-ffaa:1:5,192.168.1.5 -c 3 --dispatcher /dev/shm/dispatcher/default.sock

      addresses=("42-ffaa:1:1" "42-ffaa:1:2" "42-ffaa:1:3" "42-ffaa:1:4" "42-ffaa:1:5")

      # Iterate over each address in the array
      for address in "''${addresses[@]}"; do
          # Run the showpaths command for each address
          scion showpaths "$address" --dispatcher /dev/shm/dispatcher/default.sock

          # Run the ping command for each address
          #scion ping "$address,192.168.1.$(( ''${address##*:} ))" -c 3 --dispatcher /dev/shm/dispatcher/default.sock
          scion ping "$address,127.0.0.1" -c 3 --dispatcher /dev/shm/dispatcher/default.sock
      done

    '';
  in ''
    start_all()
    scion01.wait_for_unit("scion-control.service")
    scion02.wait_for_unit("scion-control.service")
    scion03.wait_for_unit("scion-control.service")
    scion04.wait_for_unit("scion-control.service")
    scion05.wait_for_unit("scion-control.service")
    scion01.sleep(10)
    scion01.succeed("${pingAll} >&2")
    scion02.succeed("${pingAll} >&2")
    scion03.succeed("${pingAll} >&2")
    scion04.succeed("${pingAll} >&2")
    scion05.succeed("${pingAll} >&2")
  '';
}