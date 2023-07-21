{
  # Pin nixpkgs to the commit before Go was upgraded to 1.20.5 to workaround a Docker issue
  # https://github.com/NixOS/nixpkgs/issues/244159
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/b6bbc53029a31f788ffed9ea2d459f0bb0f0fbfc";

  inputs.flake-utils.url = "github:numtide/flake-utils";

  inputs.agenix.url = "github:ryantm/agenix";
  inputs.agenix.inputs.nixpkgs.follows = "nixpkgs";

  inputs.poetry2nix.url = "github:nix-community/poetry2nix";
  inputs.poetry2nix.inputs.nixpkgs.follows = "nixpkgs";

  inputs.analytics-ingest.url = "github:dolphin-emu/analytics-ingest";
  inputs.analytics-ingest.inputs.nixpkgs.follows = "nixpkgs";
  inputs.analytics-ingest.inputs.poetry2nix.follows = "poetry2nix";

  inputs.central.url = "github:dolphin-emu/central";
  inputs.central.inputs.nixpkgs.follows = "nixpkgs";
  inputs.central.inputs.poetry2nix.follows = "poetry2nix";

  inputs.fifoci.url = "github:dolphin-emu/fifoci";
  inputs.fifoci.inputs.nixpkgs.follows = "nixpkgs";
  inputs.fifoci.inputs.poetry2nix.follows = "poetry2nix";

  inputs.netplay-index.url = "github:dolphin-emu/netplay-index";
  inputs.netplay-index.inputs.nixpkgs.follows = "nixpkgs";
  inputs.netplay-index.inputs.poetry2nix.follows = "poetry2nix";

  outputs = { self, nixpkgs, flake-utils, analytics-ingest, central, fifoci, netplay-index, ... }@attrs: {
    colmena = {
      meta.nixpkgs = import nixpkgs {
        system = "x86_64-linux";
        overlays = [
          analytics-ingest.overlay
          central.overlay
          fifoci.overlay
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
