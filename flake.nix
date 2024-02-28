{
  description = "Flake for the SCION Internet Architecture";

  # Nixpkgs / NixOS version to use.
  inputs.nixpkgs = { type = "github"; owner = "NixOS"; repo = "nixpkgs"; ref = "nixos-unstable"; };

  # Upstream source tree(s).
  inputs.scion-src = { type = "github"; owner = "scionproto"; repo = "scion"; ref = "v0.10.0"; flake = false; };

  inputs.scion-apps-src = { type = "github"; owner = "netsec-ethz"; repo = "scion-apps"; flake = false; };
  inputs.scionlab-src = { type = "github"; owner = "netsec-ethz"; repo = "scionlab"; ref = "develop"; flake = false; };
  inputs.scion-builder-src = { type = "github"; owner = "netsec-ethz"; repo = "scion-builder"; flake = false; };

  inputs.rains-src = { type = "github"; owner = "netsec-ethz"; repo = "rains"; flake = false; };

  outputs = { self, nixpkgs, scion-src, scion-apps-src, scionlab-src, scion-builder-src, rains-src, ... }@inputs:
    let
      # Generate a user-friendly version numer.
      versions =
        let
          generateVersion = builtins.substring 0 8;
        in
        nixpkgs.lib.genAttrs
          [ "scion" "scion-apps" "scionlab" "scion-builder" "rains" ]
          (n: generateVersion inputs."${n}-src".lastModifiedDate);

      # System types to support.
      supportedSystems = [ "x86_64-linux" ];

      # Helper function to generate an attrset '{ x86_64-linux = f "x86_64-linux"; ... }'.
      forAllSystems = f: nixpkgs.lib.genAttrs supportedSystems (system: f system);

      # Nixpkgs instantiated for supported system types.
      nixpkgsFor = forAllSystems (system: import nixpkgs { inherit system; overlays = [ self.overlay ]; });

    in
    {

      apps = forAllSystems (system: {
        vm = {
          type = "app";
          program = "${self.nixosConfigurations.scionlab.config.system.build.vm}/bin/run-scionlab-vm";
        };
      });

      # A Nixpkgs overlay.
      overlay = final: prev: with final.pkgs; {

        ioq3-scion = let
          fetchedAssets = fetchzip {
            url = "https://archive.org/download/baseq3/baseq3.zip";
            hash = "sha256-XdjuCeq9RegEUPMdeotpuEb1lzhyaSkpjYqBPOVyXtM=";
          };
          assets = runCommand "ioq3-assets" {} ''
            mkdir -p $out/share/ioquake3
            cp -r ${fetchedAssets} $out/share/ioquake3/baseq3
          '';
        in symlinkJoin {
          name = "ioq3-scion-with-assets";
          paths = [
            assets
            (builtins.getFlake "github:matthewcroughan/nixpkgs/f90fcd31eeb587950dc9fcdf04e7fbaa80328bcc").legacyPackages.${final.hostPlatform.system}.ioq3-scion
          ];
        };
        scion = buildGo121Module {
          pname = "scion";
          version = versions.scion;
          src = scion-src;
          vendorSha256 = "sha256-4nTp6vOyS7qDn8HmNO0NGCNU7wCb8ww8a15Yv3MPEq8=";
          postPatch = ''
            patchShebangs **/*.sh scion.sh

#            substituteInPlace go/pkg/proto/daemon/mock_daemon/daemon.go \
#              --replace ColibriList ColibriListRsvs \
#              --replace ColibriAdmissionEntryResponse ColibriAddAdmissionEntryResponse \
#              --replace ColibriAdmissionEntry ColibriAddAdmissionEntryRequest \
#              --replace ColibriCleanupRequest ColibriCleanupRsvRequest \
#              --replace ColibriCleanupResponse ColibriCleanupRsvResponse \
#              --replace ColibriSetupRequest ColibriSetupRsvRequest \
#              --replace ColibriSetupResponse ColibriSetupRsvResponse
          '';
          postInstall = ''
            cp scion.sh $out/
            ln -s $out/bin/dispatcher $out/bin/scion-dispatcher
            ln -s $out/bin/router $out/bin/scion-router
            ln -s $out/bin/control $out/bin/scion-control
            ln -s $out/bin/daemon $out/bin/scion-daemon
          '';
          doCheck = false;
        };

        scion-systemd-wrapper = stdenv.mkDerivation {
          pname = "scion-systemd-wrapper";
          version = versions.scion-builder;
          src = scion-builder-src + "/scion-systemd-wrapper";
          unpackPhase = ''
            runHook preUnpack
            cp $src scion-systemd-wrapper
            runHook postUnpack
          '';
          prePatch = ''
            sed -i 's@/bin/bash@${bash}/bin/bash@' scion-systemd-wrapper
          '';
          dontBuild = true;
          installPhase = ''
            runHook preInstall
            mkdir -p $out/bin
            cp scion-systemd-wrapper $out/bin
            runHook postInstall
          '';
        };

        scion-apps = buildGo121Module {
          pname = "scion-apps";
          version = versions.scion;
          src = scion-apps-src;
          postPatch = ''
            substituteInPlace webapp/web/tests/health/scmpcheck.sh \
              --replace "hostname -I" "hostname -i"
          '';
          buildInputs = [ openpam ];
          vendorSha256 = "sha256-aJETTd/HlzTo/FoWiGFdzfhjg2gv65vRw0EvjLIxErY=";
          postInstall = ''
            # Include symlinks to the outputs generated by the Makefile
            for f in $out/bin/*; do
              filename="$(basename "$f")"
              ln -s $f $out/bin/scion-$filename
            done

            # Include static website for webapp
            mkdir -p $out/share
            cp -r webapp/web $out/share/scion-webapp
          '';
        };

        scionlab = stdenv.mkDerivation {
          pname = "scionlab";
          version = versions.scionlab;
          src = scionlab-src + "/scionlab/hostfiles/scionlab-config";
          unpackPhase = ''
            runHook preUnpack
            cp $src scionlab-config
            runHook postUnpack
          '';
          prePatch = ''
            sed -i 's@/usr/bin/env.*@${python3}/bin/python@' scionlab-config
          '';
          dontBuild = true;
          installPhase = ''
            runHook preInstall
            mkdir -p $out/bin
            cp scionlab-config $out/bin
            runHook postInstall
          '';
        };

        rains = buildGo121Module {
          pname = "rains";
          version = versions.rains;
          src = rains-src;
          vendorSha256 = "sha256-ppJ1Z4mVdJYl1sUIlFXbiTi6Mq16PH/0iWDIn5YMIp8=";
        };

      };

      # Provide some binary packages for selected system types.
      packages = forAllSystems (system:
        let
          pkgSet = nixpkgsFor.${system};
        in
        {
          inherit (pkgSet)
            scion scion-apps scionlab
            scion-systemd-wrapper
            rains ioq3-scion;
        }
      );

      # The default package for 'nix build'. This makes sense if the
      # flake provides only one package or there is a clear "main"
      # package.
      defaultPackage = forAllSystems (system: self.packages.${system}.scion);

      # A NixOS module, if applicable (e.g. if the package provides a system service).
      nixosModules = {
        scionlab = import ./modules/scionlab.nix;
        scion-apps = import ./modules/scion-apps;
        rains = import ./modules/rains.nix;
      };

      # NixOS system configuration, if applicable
      nixosConfigurations.scionlab = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux"; # Hardcoded
        modules = [
          # VM-specific configuration
          ({ modulesPath, pkgs, ... }: {
            imports = [ (modulesPath + "/virtualisation/qemu-vm.nix") ];
            environment.systemPackages = with pkgs; [ feh chromium ];

            networking.hostName = "scionlab";
            networking.networkmanager.enable = true;

            services.xserver.enable = true;
            services.xserver.layout = "us";
            services.xserver.windowManager.i3.enable = true;
            services.xserver.displayManager.lightdm.enable = true;

            users.mutableUsers = false;
            users.users.scionlab = {
              password = "scionlab"; # yes, very secure, I know
              createHome = true;
              isNormalUser = true;
              extraGroups = [ "wheel" ];
            };
          })

          # SCIONLab support
          ({ ... }: {
            imports = [
              self.nixosModules.scionlab
              self.nixosModules.scion-apps
            ];

            nixpkgs.overlays = [ self.overlay ];
          })

          # SCIONLab configuration
          ({ ... }: {
              services.scionlab.enable = true;
              # Adjust to downloaded tarball path
              services.scionlab.configTarball = ./19-ffaa_1_fe3.tar.gz;
              services.scionlab.identifier = "19-ffaa_0_1303";

              services.scion.apps.webapp.enable = true;
              services.scion.apps.bwtester.enable = true;
          })
        ];
      };

      # Tests run by 'nix flake check' and by Hydra.
      checks = { x86_64-linux.scion-vm-test = nixpkgs.legacyPackages.x86_64-linux.callPackage ./vmtest/scion-vmtest.nix { scion = self.packages.x86_64-linux.scion; }; };

    };
}
