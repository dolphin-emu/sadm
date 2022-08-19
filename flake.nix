{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-22.05";

  inputs.agenix.url = "github:ryantm/agenix";
  inputs.agenix.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { self, nixpkgs, agenix }@attrs: {
    colmena = {
      meta.nixpkgs = import nixpkgs {
        system = "x86_64-linux";
      };
      meta.specialArgs = attrs;

      "altair.dolphin-emu.org" = import ./machines/altair;
    };
  };
}
