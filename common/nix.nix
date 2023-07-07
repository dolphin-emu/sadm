{ nixpkgs, ... }:

{
  nix.nixPath = [ "nixpkgs=${nixpkgs}" ];
  nix.gc = {
    automatic = true;
    options = "--delete-older-than 14d";
  };
  nix.settings.auto-optimise-store = true;

  # To support large builds without running out of space.
  boot.tmp.useTmpfs = false;
  boot.tmp.cleanOnBoot = true;
}
