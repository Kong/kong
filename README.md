# Introduction

This is a custom version of the Lambda plugin.

- allows for EC2 IAM roles for authorization, see https://github.com/Kong/kong/pull/2777
- has a modified version of https://github.com/Kong/kong/pull/3639
- added ECS IAM roles


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

Once enabled, it differs slightly from the original Lambda plugin in that the
token and secret are no longer required when configuring the plugin.
The behaviour is now to default to IAM roles, unless the secret and token
are provided.

When the IAM roles are used (default, if no token/secret is provided), the plugin
will first try ECS metadata, and if not available it will fallback on EC2
metadata.

## Compatibility

This plugin was developed against Kong `0.13`, and hence is compatible with
Kong Enterprise `0.33`
