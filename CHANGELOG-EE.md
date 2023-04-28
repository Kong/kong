# Unreleased 3.3

## Enterprise

### Breaking Changes

- **App-Dynamics**: plugin version has been updated to match Kong's version
  [#10646](https://github.com/Kong/kong-ee/pull/5038)

### Deprecations

### Dependencies

* `lua-resty-openssl` is bumped from 0.8.17 to 0.8.20
* `kong-openid-connect` is bumped from 2.5.4 to 2.5.5

### Features

- Starting with this release, SBOM files in SPDX and CycloneDX are now generated
for Kong Gateway's Docker images. Contact your Kong support representative to request
a copy. [KAG-739](https://konghq.atlassian.net/browse/KAG-739)
- Add a new `updated_at` field for the following core entities: ca_certificates, certificates, consumers, targets, upstreams, plugins, workspaces, clustering_data_planes, consumer_group_consumers, consumer_group_plugins, consumer_groups, credentials, document_objects, event_hooks, files, group_rbac_roles, groups, keyring_meta, legacy_files, login_attempts, parameters, rbac_role_endpoints, rbac_role_entities, rbac_roles, rbac_users, snis.
  [FTI-1292](https://konghq.atlassian.net/browse/FTI-1292)
  [FTI-1294](https://konghq.atlassian.net/browse/FTI-1294)
  [FTI-2103](https://konghq.atlassian.net/browse/FTI-2103)
  [#5018](https://github.com/Kong/kong-ee/pull/5018)
- A change on license alert in Konnect mode. [KAG-922](https://konghq.atlassian.net/browse/KAG-922)

### Fixes

* The Redis strategy of Rate Limiting should return error upon Redis Cluster is down. [FTI-4898](https://konghq.atlassian.net/browse/FTI-4898)
* Change the stats-advanced plugin name to statsd-advanced instead of statsd. [KAG-1153](https://konghq.atlassian.net/browse/KAG-1153)
* Support the plugin `ldap-auth-advanced` setting the groups to an empty array when the groups is not empty. [FTI-4730](https://konghq.atlassian.net/browse/FTI-4730)
* Websocket requests generate balancer spans when tracing is enabled. [KAG-1255](https://konghq.atlassian.net/browse/KAG-1255)
* Sending analytics to Konnect SaaS from Kong DB-less mode (in addition to DP mode) is now supported [MA-1579](https://konghq.atlassian.net/browse/MA-1579)
* Remove email field from developer registration response. [FTI-2722](https://konghq.atlassian.net/browse/FTI-2722)
* Fix the leak of UDP sockets in resty.dns.client. [FTI-4962](https://konghq.atlassian.net/browse/FTI-4962)
* Fixed an issue where management of licenses via `/licenses/` would fail if current license is not valid.
  [FTI-4927](https://konghq.atlassian.net/browse/FTI-4927)
* The systemd unit is incorrectly renamed to `kong.service` in 3.2.x.x versions, it's now reverted back to `kong-enterprise-edition.service` to keep consistent with previous releases. [KAG-878](https://konghq.atlassian.net/browse/KAG-878)

## Plugins

### Breaking Changes

### Deprecations

### Dependencies

* Update the datafile library dependency to fix a bug that caused Kong not to work when installed on a read-only file system.
  [KAG-788](https://konghq.atlassian.net/browse/KAG-788) [FTI-4873](https://konghq.atlassian.net/browse/FTI-4873)

### Features

* Request Transformer Advanced
  * The plugin now honors the following configuration parameters: untrusted_lua, untrusted_lua_sandbox_requires, untrusted_lua_sandbox_environment that make Request Transformer Advanced behave according to what is documented in the Kong Gateway configuration reference for such properties. These apply to Advanced templates (Lua expressions). (KAG-890)[https://konghq.atlassian.net/browse/KAG-890]
* Request Validator:
  * Errors are now logged for validation failures. [FTI-2465](https://konghq.atlassian.net/browse/FTI-2465)
* Proxy Cache Advanced:
  * Add wildcard and parameter match support for content_type [FTI-1131](https://konghq.atlassian.net/browse/FTI-1131)
  * add `ignore_uri_case` to configuring cache-key uri to be handled as lowercase [#10453](https://github.com/Kong/kong/pull/10453)

### Fixes

* Forward-proxy
  * Evaluates `ctx.WAITING_TIME` in forward-proxy instead of doing that in subsequent phase. This fix a bug of getting wrong `latencies.proxy` in the logging plugins.
    [FTI-1904](https://konghq.atlassian.net/browse/FTI-1904)

* Fixed an issue changing the vault name throws an error. [KAG-1070](https://konghq.atlassian.net/browse/KAG-1070)

* Rate Limiting Advanced:
  * cp should not create namespace or do sync. [FTI-4960](https://konghq.atlassian.net/browse/FTI-4960)

* Ldap-auth-advanced
  * The plugin now returns a 403 when a user isn't in the authorized groups and does authentication before authorization.
    [FTI-4955](https://github.com/Kong/kong-ee/pull/5098)

* Rate Limiting Advanced:
  * Fix a bug where the rl cluster_events broadcast the wrong data in traditional cluster mode.
    [FTI-5014](https://konghq.atlassian.net/browse/FTI-5014)

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
