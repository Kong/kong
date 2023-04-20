# Unreleased 3.3

## Enterprise

### Breaking Changes

### Deprecations

### Dependencies

* `lua-resty-openssl` is bumped from 0.8.17 to 0.8.20

### Features

### Fixes

* The Redis strategy of Rate Limiting should return error upon Redis Cluster is down. [FTI-4898](https://konghq.atlassian.net/browse/FTI-4898)
* Change the stats-advanced plugin name to statsd-advanced instead of statsd. [KAG-1153](https://konghq.atlassian.net/browse/KAG-1153)
* Support the plugin `ldap-auth-advanced` setting the groups to an empty array when the groups is not empty. [FTI-4730](https://konghq.atlassian.net/browse/FTI-4730)
* Websocket requests generate balancer spans when tracing is enabled. [KAG-1255](https://konghq.atlassian.net/browse/KAG-1255)
* Sending analytics to Konnect SaaS from Kong DB-less mode (in addition to DP mode) is now supported [MA-1579](https://konghq.atlassian.net/browse/MA-1579)

## Plugins

### Breaking Changes

### Deprecations

### Dependencies

### Features

* Request Transformer Advanced
  * The plugin now honors the following configuration parameters: untrusted_lua, untrusted_lua_sandbox_requires, untrusted_lua_sandbox_environment that make Request Transformer Advanced behave according to what is documented in the Kong Gateway configuration reference for such properties. These apply to Advanced templates (Lua expressions). (KAG-890)[https://konghq.atlassian.net/browse/KAG-890]
* Proxy Cache Advanced:
  * Add wildcard and parameter match support for content_type [FTI-1131](https://konghq.atlassian.net/browse/FTI-1131)
* Rate Limiting Advanced:
  * cp should not create namespace or do sync. [FTI-4960](https://konghq.atlassian.net/browse/FTI-4960)

### Fixes

* Forward-proxy
  * Evaluates `ctx.WAITING_TIME` in forward-proxy instead of doing that in subsequent phase. This fix a bug of getting wrong `latencies.proxy` in the logging plugins.
    [FTI-1904](https://konghq.atlassian.net/browse/FTI-1904)

* Declarative Configuration
  * Fix a bug where an HTTP 500 error was thrown while loading a declarative configuration file exported by decK containing consumer groups.
    [FTI-4808](https://konghq.atlassian.net/browse/FTI-4808)
* Fixed an issue changing the vault name throws an error. [KAG-1070](https://konghq.atlassian.net/browse/KAG-1070)

* Ldap-auth-advanced
  * The plugin now returns a 403 when a user isn't in the authorized groups and does authentication before authorization.
    [FTI-4955](https://github.com/Kong/kong-ee/pull/5098)

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
