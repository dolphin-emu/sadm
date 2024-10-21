{ self, lib, pkgs, ... }:

let
  # We need a statically built QEMU for binfmt in a containerized environment.
  qemuUser = pkgs.pkgsStatic.stdenv.mkDerivation (finalAttrs: {
    pname = "qemu-user";
    version = "8.2.6";

    src = pkgs.fetchurl {
      url = "https://download.qemu.org/qemu-${finalAttrs.version}.tar.xz";
      hash = "sha256-jK2x5rA5lU5nLUp8w6XzBzi0y5m8ksJkCxXMifj5H6I=";
    };

    nativeBuildInputs = with pkgs; [
      makeWrapper removeReferencesTo
      pkg-config flex bison meson ninja

      python3Packages.python
    ];

    buildInputs = with pkgs.pkgsStatic; [ zlib glib ];

    dontUseMesonConfigure = true;
    dontAddStaticConfigureFlags = true;

    outputs = [ "out" ];

    configureFlags = [
      "--disable-strip"
      "--localstatedir=/var"
      "--sysconfdir=/etc"
      "--static"
      "--disable-plugins"
      "--disable-system"
      "--target-list=aarch64-linux-user"
    ];

    dontWrapGApps = true;

    preBuild = "cd build";
  });
in {
  # Allow execution of arm64 executables using QEMU user-mode emulation.
  # We use this for building arm64 flatpaks.
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  # We need to override the default interpreter to use our statically built QEMU.
  # The other flags are also necessary to ensure that it works in a containerized environment.
  boot.binfmt.registrations.aarch64-linux = {
    interpreter = "${qemuUser}/bin/qemu-aarch64";
    wrapInterpreterInShell = false;
    fixBinary = true;
    matchCredentials = true;
    preserveArgvZero = true;
  };

  # TODO: Most of the above can be replaced with this on a future NixOS version.
  # boot.binfmt.preferStaticEmulators = true;
}
