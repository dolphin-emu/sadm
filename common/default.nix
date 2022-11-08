{ agenix, ... }:

{
  imports = [
    agenix.nixosModule

    ./backup.nix
    ./http.nix
    ./mail.nix
    ./monitoring.nix
    ./nix.nix
  ];
}
