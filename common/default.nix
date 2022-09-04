{ agenix, ... }:

{
  imports = [
    agenix.nixosModule
    ./http.nix
    ./monitoring.nix
  ];
}
