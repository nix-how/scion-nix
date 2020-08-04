{
  description = "Flake for the SCION Internet Architecture";

  # Nixpkgs / NixOS version to use.
  inputs.nixpkgs = { type = "github"; owner = "NixOS"; repo = "nixpkgs"; ref = "nixos-unstable"; };

  # Upstream source tree(s).
  inputs.scion-src = { type = "github"; owner = "netsec-ethz"; repo = "scion"; ref = "scionlab"; flake = false; };
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

      # A Nixpkgs overlay.
      overlay = final: prev: {

        hello = with final; stdenv.mkDerivation rec {
          name = "hello-${version}";

          src = hello-src;

          buildInputs = [ autoconf automake gettext gnulib perl gperf texinfo help2man ];

          preConfigure = ''
            mkdir -p .git # force BUILD_FROM_GIT
            ./bootstrap --gnulib-srcdir=${gnulib-src} --no-git --skip-po
          '';

          meta = {
            homepage = "https://www.gnu.org/software/hello/";
            description = "A program to show a familiar, friendly greeting";
          };
        };

      };

      # Provide some binary packages for selected system types.
      packages = forAllSystems (system:
        {
          inherit (nixpkgsFor.${system}) hello;
        }
      );

      # The default package for 'nix build'. This makes sense if the
      # flake provides only one package or there is a clear "main"
      # package.
      defaultPackage = forAllSystems (system: self.packages.${system}.hello);

      # A NixOS module, if applicable (e.g. if the package provides a system service).
      nixosModules.hello =
        { pkgs, ... }:
        {
          nixpkgs.overlays = [ self.overlay ];

          environment.systemPackages = [ pkgs.hello ];

          #systemd.services = { ... };
        };

      # Tests run by 'nix flake check' and by Hydra.
      checks = forAllSystems (system: self.packages.${system} // {

        # Additional tests, if applicable.
        test =
          with nixpkgsFor.${system};
          stdenv.mkDerivation {
            name = "hello-test-${version}";

            buildInputs = [ hello ];

            unpackPhase = "true";

            buildPhase = ''
              echo 'running some integration tests'
              [[ $(hello) = 'Hello, world!' ]]
            '';

            installPhase = "mkdir -p $out";
          };

        # A VM test of the NixOS module.
        vmTest =
          with import (nixpkgs + "/nixos/lib/testing-python.nix") {
            inherit system;
          };

          makeTest {
            nodes = {
              client = { ... }: {
                imports = [ self.nixosModules.hello ];
              };
            };

            testScript =
              ''
                start_all()
                client.wait_for_unit("multi-user.target")
                client.succeed("hello")
              '';
          };
      });

    };
}
