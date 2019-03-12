# Introduction

This is a custom version of the Lambda plugin.

It allows for IAM roles for authorization, see https://github.com/Kong/kong/pull/2777

And additionally it has a modified version of https://github.com/Kong/kong/pull/3639


## Installation

Since it is a custom version, it should be installed under its own name. To
facilitate this there is a rockspec file for use with LuaRocks.

Pack the rock (from `./kong/plugins/aws-lambda`):

```shell
> luarocks make
> luarocks pack kong-plugin-liamp
```

This results in a `rock` file: `kong-plugin-liamp-0.1.0-1.all.rock`

This file can be installed on any Kong system with:

```shell
> luarocks install kong-plugin-liamp-0.1.0-1.all.rock
```

## Usage

Since it is renamed, it will not be enabled by default, hence it must be enabled
like other custom plugins:

```shell
> export KONG_CUSTOM_PLUGINS=liamp
```

## Compatibility

This plugins was developed against Kong `0.13`, and hence is compatible with
Kong Enterprise `0.33`
