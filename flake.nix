{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-22.05";

  inputs.flake-utils.url = "github:numtide/flake-utils";

  inputs.agenix.url = "github:ryantm/agenix";
  inputs.agenix.inputs.nixpkgs.follows = "nixpkgs";

  inputs.analytics-ingest.url = "github:dolphin-emu/analytics-ingest";
  inputs.analytics-ingest.inputs.nixpkgs.follows = "nixpkgs";

  inputs.netplay-index.url = "github:dolphin-emu/netplay-index";
  inputs.netplay-index.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { self, nixpkgs, flake-utils, agenix, analytics-ingest, netplay-index }@attrs: {
    colmena = {
      meta.nixpkgs = import nixpkgs {
        system = "x86_64-linux";
        overlays = [
          analytics-ingest.overlay
          netplay-index.overlay
        ];
      };
      meta.specialArgs = attrs;

      "altair.dolphin-emu.org" = import ./machines/altair;
    };
  } // (flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = import nixpkgs {
        inherit system;
      };
    in rec {
      devShells.redmine-extra-deps-update = with pkgs; mkShell {
        buildInputs = [ bundix bundler ];
        inherit redmine;
      };
    })
  );
}