# Dolphin infrastructure configuration

This repository contains the configuration for Dolphin's various infrastructure
services -- some user facing, some developer facing.

Almost everything is configured using the Nix / NixOS ecosystem (exception:
build workers that have to run on specific Linux distribution environments).
The `roles` directory contains configuration for each individual service
running on Dolphin's infrastructure. The `machines` directory contains
configuration specific to each machine that Dolphin currently operates and what
roles map to it.

## How to build

```shell
$ colmena build
```

## How to deploy

```shell
$ colmena apply
```
