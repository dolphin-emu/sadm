{ agenix, ... }:

{
  imports = [
    agenix.nixosModules.default

    ./backup.nix
    ./flatpak.nix
    ./http.nix
    ./mail.nix
    ./monitoring.nix
    ./nix.nix
  ];
}
