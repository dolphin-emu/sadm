{ agenix, ... }:

{
  imports = [
    agenix.nixosModule

    ./backup.nix
    ./http.nix
    ./monitoring.nix
    ./nix.nix
  ];
}
