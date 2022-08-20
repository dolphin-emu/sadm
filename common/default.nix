{ agenix, ... }:

{
  imports = [
    agenix.nixosModule
    ./http.nix
  ];
}
