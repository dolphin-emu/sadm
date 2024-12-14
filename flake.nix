{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";

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

  inputs.cargo2nix.url = "github:cargo2nix/cargo2nix/main";
  inputs.cargo2nix.inputs.nixpkgs.follows = "nixpkgs";

  inputs.rust-overlay.url = "github:oxalica/rust-overlay";
  inputs.rust-overlay.inputs.nixpkgs.follows = "nixpkgs";

  inputs.discord-bot.url = "github:dolphin-emu/discord-bot";
  inputs.discord-bot.inputs.nixpkgs.follows = "nixpkgs";
  inputs.discord-bot.inputs.cargo2nix.follows = "cargo2nix";
  inputs.discord-bot.inputs.rust-overlay.follows = "rust-overlay";

  outputs = { self, nixpkgs, flake-utils, analytics-ingest, central, fifoci, netplay-index, discord-bot, ... }@attrs: {
    colmena = {
      meta.nixpkgs = import nixpkgs {
        system = "x86_64-linux";
        overlays = [
          analytics-ingest.overlay
          central.overlay
          fifoci.overlay
          netplay-index.overlay
          discord-bot.overlay
        ];
      };
      meta.specialArgs = attrs;

      "altair.dolphin-emu.org" = import ./machines/altair;
      "deneb.dolphin-emu.org" = import ./machines/deneb;
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
