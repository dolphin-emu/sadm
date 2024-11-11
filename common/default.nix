{ agenix, ... }:

{
  imports = [
    agenix.nixosModules.default

    ./flatpak.nix
    ./http.nix
    ./mail.nix
    ./monitoring.nix
    ./nix.nix
  ];
}
