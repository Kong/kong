# Unreleased 3.3

## Enterprise

### Breaking Changes

### Deprecations

### Dependencies

* `lua-resty-openssl` is bumped from 0.8.17 to 0.8.20

### Features

### Fixes

* The Redis strategy of Rate Limiting should return error upon Redis Cluster is down. [FTI-4898](https://konghq.atlassian.net/browse/FTI-4898)

## Plugins

### Breaking Changes

### Deprecations

### Dependencies

### Features

* Request Transformer Advanced
  * The plugin now honors the following configuration parameters: untrusted_lua, untrusted_lua_sandbox_requires, untrusted_lua_sandbox_environment that make Request Transformer Advanced behave according to what is documented in the Kong Gateway configuration reference for such properties. These apply to Advanced templates (Lua expressions). (KAG-890)[https://konghq.atlassian.net/browse/KAG-890]

### Fixes

# TEMPLATE

## Enterprise

### Breaking Changes

### Deprecations

### Dependencies

### Features

### Fixes

## Plugins

### Breaking Changes

### Deprecations

### Dependencies

### Features

### Fixes