# Passed to NixOS modules as "my".
rec {
  common = import ./common;
  roles = import ./roles;

  modules = {
    imports = [
      common
      roles
    ];
  };
}
