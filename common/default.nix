{ agenix, ... }:

{
  imports = [
    agenix.nixosModule

    ./http.nix
    ./monitoring.nix
    ./nix.nix
  ];
}
