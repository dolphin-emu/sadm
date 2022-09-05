# Dolphin infrastructure configuration

This repository contains the configuration for Dolphin's various infrastructure
services -- some user facing, some developer facing.

This is a heavy WIP replacing https://github.com/dolphin-emu/sadm with a NixOS
based configuration.

## How to build

```shell
$ colmena build
```

## How to deploy

```shell
$ colmena apply
```

## TODO list of things to migrate

- buildbot
- central
- changes poller
- downloads
- etherpad
- fifoci
- grafana
- prometheus
- redmine
- symbols
- update
