{ agenix, ... }:

{
  imports = [
    agenix.nixosModules.default

    ./backup.nix
    ./http.nix
    ./mail.nix
    ./monitoring.nix
    ./nix.nix
  ];
}
