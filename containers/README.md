This directory contains configurations for containers running on imperative,
non-NixOS systems. These are required for running builds and tests on specific
environments we care about, with all the same expected software versions.

Currently the containers are built on-demand and manually. They are pushed to a
private Docker registry (`oci-registry.dolphin-emu.org`). Automation TBD.

## How to build

```shell
$ img build ubuntu-lts-builder -o type=image,name=oci-registry.dolphin-emu.org/ubuntu-lts-builder:latest,push=true
```
