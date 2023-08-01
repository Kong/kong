**Note:** This file is for changes that only affects EE. For OSS changes, they should go into `CHANGELOG.md` in the OSS repo and be cherry-picked to the `CHANGELOG.md` file inside EE instead.

# Table of Contents

- [3.4.0.0](#3400)
- [3.3.0.0](#3300)

# Unreleased

### Fixes

* Fix the return info and log of previous errors are missing when use redis cluster mode connection fails. #6032

# 3.4.0.0

## Enterprise

### Breaking Changes

- Ubuntu 18.04 artifacts are no longer supported as it's EOL
- AmazonLinux 2022 artifacts are renamed to AmazonLinux 2023 according to AWS's decision
- Remove option `declarative_config_encryption_mode` in kong.conf and disable LMDB encryption. [FTI-5068](https://konghq.atlassian.net/browse/FTI-5068)

### Deprecations

- **Alpine packages, Docker images are now removed from the release and are no longer supported in future versions.**
- The `/consumer_groups/:id/overrides` feature is deprecated in favor of the more generic plugin scoping mechanism.
  [KAG-666](https://konghq.atlassian.net/browse/KAG-666)
- **CentOS packages are now removed from the release and are no longer supported in future versions.**
- Renamed configuration property `admin_api_uri` to `admin_gui_api_url`.
  The old `admin_api_uri` property is considered deprecated and will be
  fully removed in a future version of Kong.
  [#5984](https://github.com/Kong/kong-ee/pull/5984)
  [KAG-2037](https://konghq.atlassian.net/browse/KAG-2037)

### Dependencies

* `kong-redis-cluster` is bumped from 1.5.0 to 1.5.1
* `lua-resty-ljsonschema` is bumped from 1.1.3 to 1.15
* `lua-resty-kafka` is bumped from 0.15 to 0.16
* `OpenSSL` is bumped from 1.1.1t to 3.0.8
* `lua-resty-aws` is bumped from 1.2.2 to 1.2.3


### Features

* The Redis strategy of Rate Limiting catches strategy connection failure. [#4810](https://github.com/Kong/kong-ee/pull/4810)
* Introduces a new parameter `cascade` to support workspace cascade delete. [FTI-4731](https://konghq.atlassian.net/browse/FTI-4731)
* Plugins can now be scoped to `Consumer Groups`. [KAG-666](https://konghq.atlassian.net/browse/KAG-666)
* Added a new `ttl` option to vault configurations, allowing users to define the interval at which references are automatically re-fetched from the configured vault. [KAG-675](https://konghq.atlassian.net/browse/KAG-675)

### Fixes

* Fix a potential memory leak and reconnection problem which will probably occur when telemetry breaks down due to any exceptions in its `send` thread. [FTI-5225](https://konghq.atlassian.net/browse/FTI-5225)
* Fix the bug that will cause the telemetry websocket to be broken when there is a bad latency in flushing vitals to database by decoupling the process of receving vitals data from DP and the process of flushing vitals to database in the side of CP with a queue as a buffer. [FTI-4386](https://konghq.atlassian.net/browse/FTI-4386)
* Fix the bug of getting empty request_id when generating auditting data. [FTI-2438](https://konghq.atlassian.net/browse/FTI-2438)
* Fix a bug that would cause an error when the header x-datadog-parent-id is not passed to Kong. [KAG-1642](https://konghq.atlassian.net/browse/KAG-1642)
* Fix a queueing related bug that caused the event-hooks feature to
  not work in release 3.3.0.0 [KAG-1760](https://konghq.atlassian.net/browse/KAG-1760)
* Fix an issue where a crashing Go plugin server process would cause subsequent
  requests proxied through Kong to execute Go plugins with inconsistent configurations.
  The issue only affects scenarios where the same Go plugin is applied to different Route not work in release 3.3.0.0 [KAG-1760](https://konghq.atlassian.net/browse/KAG-1760)
* Update the datafile library to make the SAML plugin work again when
  Kong is controlled by systemd [KAG-1832](https://konghq.atlassian.net/browse/KAG-1832)
* Fix an issue that sometimes can't attach workspace with the cache's consumer well. [FTI-4564](https://konghq.atlassian.net/browse/FTI-4564)
* Fix CORS incorrect behavior when KM integrated with Portal GUI. [FTI-1437](https://konghq.atlassian.net/browse/FTI-1437)
* Fix the bug that will cause the telemetry websocket in Konnect mode between CP and DP to be broken due to unexpected payloads when counter of request equals zero. [KAG-1900](https://konghq.atlassian.net/browse/KAG-1900)
* Fix a bug where Kong Manager doesn't get the latest kconfig while the license posted via admin API. [FTI-5135](https://konghq.atlassian.net/browse/FTI-5135)
* Fix LuaJIT crash on Arm64 and enable JIT on M1. [KAG-2028](https://konghq.atlassian.net/browse/KAG-2028)
* Fixed an issue where the license cannot load when pulling `KONG_LICENSE_DATA` from Vault. [FTI-4856](https://konghq.atlassian.net/browse/FTI-4856)
* Fixed an issue in the Dev Portal when attempting to expand an API. [FTI-4899](https://konghq.atlassian.net/browse/FTI-4899)

## Plugins

### Breaking Changes

### Deprecations

### Dependencies

### Features

- OpenID-Connect now support error reason header, and it can be turned off with `expose_error_code` set to false.
  [FTI-1882](https://konghq.atlassian.net/browse/FTI-1882)
- Kafka-Log now supports the `custom_fields_by_lua` configuration for dynamic modification of log fields using lua code just like other log plugins.
  [FTI-5127](https://konghq.atlassian.net/browse/FTI-5127)
- OpenID-Connect now supports adding scope to the token cache key with `token_cache_key_include_scope` set to true.
  [KAG-1439](https://konghq.atlassian.net/browse/KAG-1439)
- graphql-rate-limiting-advanced now support config with upstream target.
  [FTI-5209](https://konghq.atlassian.net/browse/FTI-5209)
- Add workspace name to the logging payload.
  [FTI-4728](https://konghq.atlassian.net/browse/FTI-4728)

### Fixes

* Oauth 2.0 Introspection plugin fails when request with JSON that is not a table. [FTI-4974](https://konghq.atlassian.net/browse/FTI-4974)
* Portal documentation page: field `registration` in `document_object` will not be set
  when the plugin `Portal Application Registration` is installed but not enabled.
  [FTI-4798](https://konghq.atlassian.net/browse/FTI-4798)
* **gRPC-Gateway**: fix an issue where an array with one element would fail to be encoded.
  [FTI-5074](https://konghq.atlassian.net/browse/FTI-5074)
* **Mtls-auth**: Fix a bug that would cause an unexpected error when `skip_consumer_lookup` is enabled and `authenticated_group_by` is set to `null`.
  [FTI-5101](https://konghq.atlassian.net/browse/FTI-5101)
* Fix an issue that Request-Transformer-Advanced does not transform the response body while upstream returns a Content-Type with +json suffix at subtype.
  [FTI-4959](https://konghq.atlassian.net/browse/FTI-4959)
* **OpenID-Connect**: Log levels of many error message of OIDC are increased.
* **OpenID-Connect**: Changes some log's level from `notice` to `error` for better visibility.
  [FTI-2884](https://konghq.atlassian.net/browse/FTI-2884)
* **Mocking**: Fix a bug that the plugin throws an error when the arbitrary elements are defined in the path node.
* **Mtls-Auth**: Fix several revocation verification issues where
  1. If `revocation_check_mode=IGNORE_CA_ERROR` then the crl revocation failure will be ignored.
  2. Once a crl is added into the store, it will always do crl revocation check with this crl file.
  3. OCSP verification fails with `no issuer certificate in chain` error if the client only sends a leaf certificate.
  4. A optimization of crl revocation verification.
  5. `http_timeout` is not correctly set
  [FTI-5058](https://konghq.atlassian.net/browse/FTI-5058)
  [FTI-3060](https://konghq.atlassian.net/browse/FTI-3060)
  [FTI-5223](https://konghq.atlassian.net/browse/FTI-5223)
* OAS Validation
  * Fix a bug that the plugin is unable to pass the validation even if path parameter is valid. [FTI-4965](https://konghq.atlassian.net/browse/FTI-4965)
  * Fix an issue that the plugin always validates the request body even if the method spec has no requestBody defined. [FTI-4967](https://konghq.atlassian.net/browse/FTI-4967)
* OpenID-Connect
  * Correctly set the right table key on 'log' and 'message'.
  * If an invalid opaque token is provided but verified failed, print the correct error.


## Kong Manager

### Breaking Changes

### Deprecations

### Dependencies

### Features

* Enhanced the user experience of entity editing pages with a refined look and feel. [KAG-1453](https://konghq.atlassian.net/browse/KAG-1453) [KAG-1568](https://konghq.atlassian.net/browse/KAG-1568)
* Simplified the user path by removing the configuration pages for nested entities. [KAG-1660](https://konghq.atlassian.net/browse/KAG-1660)

### Fixes

* Fixes an issue using OIDC does not handle `invalid credentials` when providing wrong usename. [FTI-5194](https://konghq.atlassian.net/browse/FTI-5194)
* Add an alert message in the `admins tab` page for `workspace access` while the admin_auth is set to `openid-connect`. [FTI-5085](https://konghq.atlassian.net/browse/FTI-5085)
* Fixed an issue the custom permission endpoint not work. [#FTI-5053](https://konghq.atlassian.net/browse/FTI-5053)

# 3.3.0.0

## Enterprise

### Breaking Changes

- **App-Dynamics**: plugin version has been updated to match Kong's version
  [#10646](https://github.com/Kong/kong-ee/pull/5038)

### Deprecations

### Dependencies

* `lua-resty-openssl` is bumped from 0.8.17 to 0.8.20
* `kong-openid-connect` is bumped from 2.5.4 to 2.5.5
* `lua-resty-aws` is bumped from 1.1.2 to 1.2.2
* `lua-resty-gcp` is bumped from 0.0.11 to 0.0.12

### Features

- Starting with this release, when using the secret management with an AWS/GCP backend, the backend server's certificate will be validate if it goes through HTTPS.
- Starting with this release, when using the Data Plane resilience feature, the server-side certificate of the backend S3/GCS service will be validated if it goes through HTTPS.
- Starting with this release, SBOM files in SPDX and CycloneDX are now generated
for Kong Gateway's Docker images. Contact your Kong support representative to request
a copy. [KAG-739](https://konghq.atlassian.net/browse/KAG-739)
- Add a new `updated_at` field for the following core entities: ca_certificates, certificates, consumers, targets, upstreams, plugins, workspaces, clustering_data_planes, consumer_group_consumers, consumer_group_plugins, consumer_groups, credentials, document_objects, event_hooks, files, group_rbac_roles, groups, keyring_meta, legacy_files, login_attempts, parameters, rbac_role_endpoints, rbac_role_entities, rbac_roles, rbac_users, snis.
  [FTI-1292](https://konghq.atlassian.net/browse/FTI-1292)
  [FTI-1294](https://konghq.atlassian.net/browse/FTI-1294)
  [FTI-2103](https://konghq.atlassian.net/browse/FTI-2103)
  [#5018](https://github.com/Kong/kong-ee/pull/5018)
- A change on license alert in Konnect mode. [KAG-922](https://konghq.atlassian.net/browse/KAG-922)
* **JWT Signer**: support new configuration field `add_claims`, to add extra claims to JWT. [FTI-1993](https://konghq.atlassian.net/browse/FTI-1993)
- A different alerting strategy of licensing expiry is made for dataplanes in Konnect mode. If there are at least 16 days left before expiration, no alerts will be issued. If within 16 days, a warning level alert will be issued everyday. If expired, a critical level alert will be issued everyday. [KAG-922](https://konghq.atlassian.net/browse/KAG-922)
- Kong Enterprise now supports using the AWS IAM database authentication to connect to the RDS(Postgres) database.
  [KAG-89](https://konghq.atlassian.net/browse/KAG-89)
  [KAG-167](https://konghq.atlassian.net/browse/KAG-167)

#### Kong Manager

* Now Kong Manager and Konnect shares the same UI for navbar, sidebar and all entity lists. [KAG-694](https://konghq.atlassian.net/browse/KAG-694)
* Improved display for Routes list when Expressions router is enabled. [KAG-649](https://konghq.atlassian.net/browse/KAG-649)
* Support CA Certificates and TLS Verify in Gateway Service Form. [KAG-853](https://konghq.atlassian.net/browse/KAG-853)
* Added a GitHub star in free mode navbar. [KAG-746](https://konghq.atlassian.net/browse/KAG-746)
* Upgraded Konnect CTA in free mode. [KAG-1205](https://konghq.atlassian.net/browse/KAG-1205)


### Fixes

* Resolved an issue with the plugin iterator where sorting would become mixed up when dynamic reordering was applied. This fix ensures proper sorting behavior in all scenarios. [FTI-4945](https://konghq.atlassian.net/browse/FTI-4945)

* The Redis strategy of Rate Limiting should return error upon Redis Cluster is down. [FTI-4898](https://konghq.atlassian.net/browse/FTI-4898)
* Change the stats-advanced plugin name to statsd-advanced instead of statsd. [KAG-1153](https://konghq.atlassian.net/browse/KAG-1153)
* Support the plugin `ldap-auth-advanced` setting the groups to an empty array when the groups is not empty. [FTI-4730](https://konghq.atlassian.net/browse/FTI-4730)
* Websocket requests generate balancer spans when tracing is enabled. [KAG-1255](https://konghq.atlassian.net/browse/KAG-1255)
* Sending analytics to Konnect SaaS from Kong DB-less mode (in addition to DP mode) is now supported [MA-1579](https://konghq.atlassian.net/browse/MA-1579)
* Remove email field from developer registration response. [FTI-2722](https://konghq.atlassian.net/browse/FTI-2722)
* Fix the leak of UDP sockets in resty.dns.client. [FTI-4962](https://konghq.atlassian.net/browse/FTI-4962)
* Fixed an issue where management of licenses via `/licenses/` would fail if current license is not valid.
  [FTI-4927](https://konghq.atlassian.net/browse/FTI-4927)
* Add missing schema field `protocols` for `jwe-decrypt`, `oas-validation`, and `vault-auth`.
  [KAG-754](https://konghq.atlassian.net/browse/KAG-754)
* The systemd unit is incorrectly renamed to `kong.service` in 3.2.x.x versions, it's now reverted back to `kong-enterprise-edition.service` to keep consistent with previous releases. [KAG-878](https://konghq.atlassian.net/browse/KAG-878)
* Fix failure to generate keyring when RBAC is enabled.
  [FTI-4863](https://konghq.atlassian.net/browse/FTI-4863)
* Fix `lua_ssl_verify_depth` in FIPS mode to match the same depth of normal mode.
  [KAG-1500](https://konghq.atlassian.net/browse/KAG-1500).

#### Kong Manager

* Fixed an issue where the VerticalTabs’ content becomes blank on selecting a tab that is currently active. [KAG-1032](https://konghq.atlassian.net/browse/KAG-1032)
* Fixed an issue where the `/register` route jumps to `/login` occasionally. [KAG-1282](https://konghq.atlassian.net/browse/KAG-1282)
* Fixed an issue where the statsD plugin has custom identifier field under metric which does not exist in schema. [KAG-1138](https://konghq.atlassian.net/browse/KAG-1138)
* Endpoint to list consumer groups under a consumer now reflects latest changes on consumer groups. [KAG-1378](https://konghq.atlassian.net/browse/KAG-1378)
* Fix the cache issue of route-by-header plugin, where config change does not take effect. [FTI-5017](https://konghq.atlassian.net/browse/FTI-5017)

## Plugins

### Breaking Changes

### Deprecations

### Dependencies

* Update the datafile library dependency to fix a bug that caused Kong not to work when installed on a read-only file system.
  [KAG-788](https://konghq.atlassian.net/browse/KAG-788) [FTI-4873](https://konghq.atlassian.net/browse/FTI-4873)
* Update the datafile library dependency to fix a bug that caused Kong
  not to work when started from systemd
  [KAG-1466](https://konghq.atlassian.net/browse/KAG-1466)
  [FTI-5047](https://konghq.atlassian.net/browse/FTI-5047)

### Features

* Request Transformer Advanced
  * The plugin now honors the following configuration parameters: untrusted_lua, untrusted_lua_sandbox_requires, untrusted_lua_sandbox_environment that make Request Transformer Advanced behave according to what is documented in the Kong Gateway configuration reference for such properties. These apply to Advanced templates (Lua expressions). (KAG-890)[https://konghq.atlassian.net/browse/KAG-890]
* Request Validator:
  * Errors are now logged for validation failures. [FTI-2465](https://konghq.atlassian.net/browse/FTI-2465)
* Proxy Cache Advanced:
  * Add wildcard and parameter match support for content_type [FTI-1131](https://konghq.atlassian.net/browse/FTI-1131)
  * add `ignore_uri_case` to configuring cache-key uri to be handled as lowercase [#10453](https://github.com/Kong/kong/pull/10453)

### Fixes

* Request Validator
  * The validation function for the allowed_content_types parameter was too strict, making it impossible to use media types that contained a "-" character.  This issue has been fixed. [FTI-4725](https://konghq.atlassian.net/browse/FTI-4725)

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

## Kong Manager

### Breaking Changes

### Deprecations

### Dependencies

### Features

### Fixes
