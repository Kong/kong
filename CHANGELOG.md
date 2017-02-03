## [Unreleased][unreleased]

## [0.9.9] - 2017/02/02

### Fixed

- Correctly put Cassandra sockets into the Nginx connection pool for later
  reuse. This greatly improves the performance for rate-limiting and
  response-ratelimiting plugins.
  [f8f5306](https://github.com/Mashape/kong/commit/f8f53061207de625a29bbe5d80f1807da468a1bc)
- Correct length of a year in seconds for rate-limiting and
  response-ratelimiting plugins. A year was wrongly assumed to only be 360
  days long.
  [e4fdb2a](https://github.com/Mashape/kong/commit/e4fdb2a3af4a5f2bf298c7b6488d88e67288c98b)
- Prevent misinterpretation of the `%` character in proxied URLs encoding.
  Thanks Thomas Jouannic for the patch.
  [#1998](https://github.com/Mashape/kong/pull/1998)
  [#2040](https://github.com/Mashape/kong/pull/2040)

## [0.9.8] - 2017/01/19

### Fixed

- Properly set the admin IP in the Serf script.

### Changed

- Provide negative-caching for missed database entities. This should improve
  performance in some cases.
  [#1914](https://github.com/Mashape/kong/pull/1914)

### Fixed

- Plugins:
  - Fix fault tolerancy logic and error reporting in rate-limiting plugins.

## [0.9.7] - 2016/12/21

### Fixed

- Fixed a performance issue in Cassandra by removing an old workaround that was
  forcing Cassandra to use LuaSocket instead of cosockets.
  [#1916](https://github.com/Mashape/kong/pull/1916)
- Fixed an issue that was causing a recursive attempt to stop Kong's services
  when an error was occurring.
  [#1877](https://github.com/Mashape/kong/pull/1877)
- Custom plugins are now properly loaded again.
  [#1910](https://github.com/Mashape/kong/pull/1910)
- Plugins:
  - Galileo: properly encode empty arrays.
    [#1909](https://github.com/Mashape/kong/pull/1909)
  - OAuth 2: implements a missing Postgres migration for `redirect_uri` in
    every OAuth 2 credential. [#1911](https://github.com/Mashape/kong/pull/1911)
  - OAuth 2: safely parse the request body even when no data has been sent.
    [#1915](https://github.com/Mashape/kong/pull/1915)

## [0.9.6] - 2016/11/29

### Fixed

- Resolve support for PostgreSQL SSL connections.
  [#1720](https://github.com/Mashape/kong/issues/1720)
- Ensure `kong start` honors the `--conf` flag is a config file already exists
  at one of the default locations (`/etc/kong.conf`, `/etc/kong/kong.conf`).
  [#1681](https://github.com/Mashape/kong/pull/1681)
- Obfuscate sensitive properties from the `/` Admin API route which returns
  the current node's configuration.
  [#1650](https://github.com/Mashape/kong/pull/1650)

## [0.9.5] - 2016/11/07

### Changed

- Dropping support for OpenResty 1.9.15.1 in favor of 1.11.2.1
  [#1797](https://github.com/Mashape/kong/pull/1797)

### Fixed

- Fixed an error (introduced in 0.9.4) in the auto-clustering event

## [0.9.4] - 2016/11/02

### Fixed

- Fixed the random string generator that was causing some problems, especially
  in Serf for clustering. [#1754](https://github.com/Mashape/kong/pull/1754)
- Seed random number generator in CLI.
  [#1641](https://github.com/Mashape/kong/pull/1641)
- Reducing log noise in the Admin API.
  [#1781](https://github.com/Mashape/kong/pull/1781)
- Fixed the reports lock implementation that was generating a periodic error
  message. [#1783](https://github.com/Mashape/kong/pull/1783)

## [0.9.3] - 2016/10/07

### Added

- Added support for Serf 0.8. [#1693](https://github.com/Mashape/kong/pull/1693)

### Fixed

- Properly invalidate global plugins.
  [#1723](https://github.com/Mashape/kong/pull/1723)

## [0.9.2] - 2016/09/20

### Fixed

- Correctly report migrations errors. This was caused by an error being thrown
  from the error handler, and superseding the actual error. [#1605]
  (https://github.com/Mashape/kong/pull/1605)
- Prevent Kong from silently failing to start. This would be caused by an
  erroneous error handler. [28f5d10]
  (https://github.com/Mashape/kong/commit/28f5d10)
- Only report a random number generator seeding error when it is not already
  seeded. [#1613](https://github.com/Mashape/kong/pull/1613)
- Reduce intra-cluster noise by not propagating keepalive requests events.
  [#1660](https://github.com/Mashape/kong/pull/1660)
- Admin API:
  - Obfuscates sensitive configuration settings from the `/` route.
    [#1650](https://github.com/Mashape/kong/pull/1650)
- CLI:
  - Prevent a failed `kong start` to stop an already running Kong node.
    [#1645](https://github.com/Mashape/kong/pull/1645)
  - Remove unset configuration placeholders from the nginx configuration
    template. This would occur when no Internet connection would be
    available and would cause Kong to compile an erroneous nginx config.
    [#1606](https://github.com/Mashape/kong/pull/1606)
  - Properly count the number of executed migrations.
    [#1649](https://github.com/Mashape/kong/pull/1649)
- Plugins:
  - OAuth2: remove the "Kong" mentions in missing `provision_key` error
    messages. [#1633](https://github.com/Mashape/kong/pull/1633)
  - OAuth2: allow to correctly delete applications when using Cassandra.
    [#1659](https://github.com/Mashape/kong/pull/1659)
  - galileo: provide a default `bodySize` value when `log_bodies=true` but the
    current request/response has no body.
    [#1657](https://github.com/Mashape/kong/pull/1657)

## [0.9.1] - 2016/09/02

### Added

- Plugins:
  - ACL: allow to retrieve/update/delete an ACL by group name.
    [#1544](https://github.com/Mashape/kong/pull/1544)
  - Basic Authentication: allow to retrieve/update/delete a credential by `username`.
    [#1570](https://github.com/Mashape/kong/pull/1570)
  - HMAC Authentication: allow to retrieve/update/delete a credential by `username`.
    [#1570](https://github.com/Mashape/kong/pull/1570)
  - JWT Authentication: allow to retrieve/update/delete a credential by `key`.
    [#1570](https://github.com/Mashape/kong/pull/1570)
  - Key Authentication: allow to retrieve/update/delete a credential by `key`.
    [#1570](https://github.com/Mashape/kong/pull/1570)
  - OAuth2 Authentication: allow to retrieve/update/delete a credential by `client_id` and tokens by `access_token`.
    [#1570](https://github.com/Mashape/kong/pull/1570)

### Fixed

- Correctly parse configuration file settings contaning comments.
  [#1569](https://github.com/Mashape/kong/pull/1569)
- Prevent third-party Lua modules (and plugins) to override the seed for random
  number generation. This prevents the creation of conflicitng UUIDs.
  [#1558](https://github.com/Mashape/kong/pull/1558)
- Use [pgmoon-mashape](https://github.com/Mashape/pgmoon) `2.0.0` which
  properly namespaces our fork, avoiding conflicts with other versions of
  pgmoon, such as the one installed by Lapis.
  [#1582](https://github.com/Mashape/kong/pull/1582)
- Avoid exposing OpenResty's information on HTTP `4xx` errors.
  [#1567](https://github.com/Mashape/kong/pull/1567)
- ulimit with `unlimited` value is now properly handled.
  [#1545](https://github.com/Mashape/kong/pull/1545)
- CLI:
  - Stop third-party services (dnsmasq/Serf) when Kong could not start.
    [#1588](https://github.com/Mashape/kong/pull/1588)
  - Prefix database migration errors (such as Postgres' `connection refused`)
    with the database name (`postgres`/`cassandra`) to avoid confusions.
    [#1583](https://github.com/Mashape/kong/pull/1583)
- Plugins:
  - galileo: Use `Content-Length` header to get request/response body size when
    `log_bodies` is disabled.
    [#1584](https://github.com/Mashape/kong/pull/1584)
- Admin API:
  - Revert the `/plugins/enabled` endpoint's response to be a JSON array, and
    not an Object. [#1529](https://github.com/Mashape/kong/pull/1529)

## [0.9.0] - 2016/08/18

The main focus of this release is Kong's new CLI. With a simpler configuration file, new settings, environment variables support, new commands as well as a new interpreter, the new CLI gives more power and flexibility to Kong users and allow for an easier integration in your deployment workflow, as well as better testing for developers and plugins authors. Additionally, some new plugins and performance improvements are included as well as the regular bug fixes.

### Changed

- :warning: PostgreSQL is the new default datastore for Kong. If you were using Cassandra and you are upgrading, you need to explicitly set `cassandra` as your `database`.
- :warning: New CLI, with new commands and refined arguments. This new CLI uses the `resty-cli` interpreter (see [lua-resty-cli](https://github.com/openresty/resty-cli)) instead of LuaJIT. As a result, the `resty` executable must be available in your `$PATH` (resty-cli is shipped in the OpenResty bundle) as well as the `bin/kong` executable. Kong does not rely on Luarocks installing the `bin/kong` executable anymore. This change of behavior is taken care of if you are using one of the official Kong packages.
- :warning: Kong uses a new configuration file, with an easier syntax than the previous YAML file.
- New arguments for the CLI, such as verbose, debug and tracing flags. We also avoid requiring the configuration file as an argument to each command as per the previous CLI.
- Customization of the Nginx configuration can now be taken care of using two different approaches: with a custom Nginx configuration template and using `kong start --template <file>`, or by using `kong compile` to generate the Kong Nginx sub-configuration, and `include` it in a custom Nginx instance.
- Plugins:
  - Rate Limiting: the `continue_on_error` property is now called `fault_tolerant`.
  - Response Rate Limiting: the `continue_on_error` property is now called `fault_tolerant`.

### Added

- :fireworks: Support for overriding configuration settings with environment variables.
- :fireworks: Support for SSL connections between Kong and PostgreSQL. [#1425](https://github.com/Mashape/kong/pull/1425)
- :fireworks: Ability to apply plugins with more granularity: per-consumer, and global plugins are now possible. [#1403](https://github.com/Mashape/kong/pull/1403)
- New `kong check` command: validates a Kong configuration file.
- Better version check for third-party dependencies (OpenResty, Serf, dnsmasq). [#1307](https://github.com/Mashape/kong/pull/1307)
- Ability to configure the validation depth of database SSL certificates from the configuration file. [#1420](https://github.com/Mashape/kong/pull/1420)
- `request_host`: internationalized url support; utf-8 domain names through punycode support and paths through %-encoding. [#1300](https://github.com/Mashape/kong/issues/1300)
- Implements caching locks when fetching database configuration (APIs, Plugins...) to avoid dog pile effect on cold nodes. [#1402](https://github.com/Mashape/kong/pull/1402)
- Plugins:
  - :fireworks: **New bot-detection plugin**: protect your APIs by detecting and rejecting common bots and crawlers. [#1413](https://github.com/Mashape/kong/pull/1413)
  - correlation-id: new "tracker" generator, identifying requests per worker and connection. [#1288](https://github.com/Mashape/kong/pull/1288)
  - request/response-transformer: ability to add strings including colon characters. [#1353](https://github.com/Mashape/kong/pull/1353)
  - rate-limiting: support for new rate-limiting policies (`cluster`, `local` and `redis`), and for a new `limit_by` property to force rate-limiting by `consumer`, `credential` or `ip`.
  - response-rate-limiting: support for new rate-limiting policies (`cluster`, `local` and `redis`), and for a new `limit_by` property to force rate-limiting by `consumer`, `credential` or `ip`.
  - galileo: performance improvements of ALF serialization. ALFs are not discarded when exceeding 20MBs anymore. [#1463](https://github.com/Mashape/kong/issues/1463)
  - statsd: new `upstream_stream` latency metric. [#1466](https://github.com/Mashape/kong/pull/1466)
  - datadog: new `upstream_stream` latency metric and tagging support for each metric. [#1473](https://github.com/Mashape/kong/pull/1473)

### Removed

- We now use [lua-resty-jit-uuid](https://github.com/thibaultCha/lua-resty-jit-uuid) for UUID generation, which is a pure Lua implementation of [RFC 4122](https://www.ietf.org/rfc/rfc4122.txt). As a result, libuuid is not a dependency of Kong anymore.

### Fixed

- Sensitive configuration settings are not printed to stdout anymore. [#1256](https://github.com/Mashape/kong/issues/1256)
- Fixed bug that caused nodes to remove themselves from the database when they attempted to join the cluster. [#1437](https://github.com/Mashape/kong/pull/1437)
- Plugins:
  - request-size-limiting: use proper constant for MB units while setting the size limit. [#1416](https://github.com/Mashape/kong/pull/1416)
  - OAuth2: security and config validation fixes. [#1409](https://github.com/Mashape/kong/pull/1409) [#1112](https://github.com/Mashape/kong/pull/1112)
  - request/response-transformer: better validation of fields provided without a value. [#1399](https://github.com/Mashape/kong/pull/1399)
  - JWT: handle some edge-cases that could result in HTTP 500 errors. [#1362](https://github.com/Mashape/kong/pull/1362)

> **internal**
> - new test suite using resty-cli and removing the need to monkey-patch the `ngx` global.
> - custom assertions and new helper methods (`wait_until()`) to gracefully fail in case of timeout.
> - increase atomicity of the testing environment.
> - lighter testing instance, only running 1 worker and not using dnsmasq by default.

## [0.8.3] - 2016/06/01

This release includes some bugfixes:

### Changed

- Switched the log level of the "No nodes found in cluster" warning to `INFO`, that was printed when starting up the first Kong node in a new cluster.
- Kong now requires OpenResty `1.9.7.5`.

### Fixed

- New nodes are now properly registered into the `nodes` table when running on the same machine. [#1281](https://github.com/Mashape/kong/pull/1281)
- Fixed a failed error parsing on Postgres. [#1269](https://github.com/Mashape/kong/pull/1269)
- Plugins:
  - Response Transformer: Slashes are now encoded properly, and fixed a bug that hang the execution of the plugin. [#1257](https://github.com/Mashape/kong/pull/1257) and [#1263](https://github.com/Mashape/kong/pull/1263)
  - JWT: If a value for `algorithm` is missing, it's now `HS256` by default. This problem occured when migrating from older versions of Kong.
  - OAuth 2.0: Fixed a Postgres problem that was preventing an application from being created, and fixed a check on the `redirect_uri` field. [#1264](https://github.com/Mashape/kong/pull/1264) and [#1267](https://github.com/Mashape/kong/issues/1267)

## [0.8.2] - 2016/05/25

This release includes bugfixes and minor updates:

### Added

- Support for a simple slash in `request_path`. [#1227](https://github.com/Mashape/kong/pull/1227)
- Plugins:
  - Response Rate Limiting: it now appends usage headers to the upstream requests in the form of `X-Ratelimit-Remaining-{limit_name}` and introduces a new `config.block_on_first_violation` property. [#1235](https://github.com/Mashape/kong/pull/1235)

#### Changed

- Plugins:
  - **Mashape Analytics: The plugin is now called "Galileo", and added support for Galileo v3. [#1159](https://github.com/Mashape/kong/pull/1159)**

#### Fixed

- Postgres now relies on the `search_path` configured on the database and its default value `$user, public`. [#1196](https://github.com/Mashape/kong/issues/1196)
- Kong now properly encodes an empty querystring parameter like `?param=` when proxying the request. [#1210](https://github.com/Mashape/kong/pull/1210)
- The configuration now checks that `cluster.ttl_on_failure` is at least 60 seconds. [#1199](https://github.com/Mashape/kong/pull/1199)
- Plugins:
  - Loggly: Fixed an issue that was triggering 400 and 500 errors. [#1184](https://github.com/Mashape/kong/pull/1184)
  - JWT: The `TYP` value in the header is not optional and case-insensitive. [#1192](https://github.com/Mashape/kong/pull/1192)
  - Request Transformer: Fixed a bug when transforming request headers. [#1202](https://github.com/Mashape/kong/pull/1202)
  - OAuth 2.0: Multiple redirect URIs are now supported. [#1112](https://github.com/Mashape/kong/pull/1112)
  - IP Restriction: Fixed that prevented the plugin for working properly when added on an API. [#1245](https://github.com/Mashape/kong/pull/1245)
  - CORS: Fixed an issue when `config.preflight_continue` was enabled. [#1240](https://github.com/Mashape/kong/pull/1240)

## [0.8.1] - 2016/04/27

This release includes some fixes and minor updates:

### Added

- Adds `X-Forwarded-Host` and `X-Forwarded-Prefix` to the upstream request headers. [#1180](https://github.com/Mashape/kong/pull/1180)
- Plugins:
  - Datadog: Added two new metrics, `unique_users` and `request_per_user`, that log the consumer information. [#1179](https://github.com/Mashape/kong/pull/1179)

### Fixed

- Fixed a DAO bug that affected full entity updates. [#1163](https://github.com/Mashape/kong/pull/1163)
- Fixed a bug when setting the authentication provider in Cassandra.
- Updated the Cassandra driver to v0.5.2.
- Properly enforcing required fields in PUT requests. [#1177](https://github.com/Mashape/kong/pull/1177)
- Fixed a bug that prevented to retrieve the hostname of the local machine on certain systems. [#1178](https://github.com/Mashape/kong/pull/1178)

## [0.8.0] - 2016/04/18

This release includes support for PostgreSQL as Kong's primary datastore!

### Breaking changes

- Remove support for the long deprecated `/consumers/:consumer/keyauth/` and `/consumers/:consumer/basicauth/` routes (deprecated in `0.5.0`). The new routes (available since `0.5.0` too) use the real name of the plugin: `/consumers/:consumer/key-auth` and `/consumers/:consumer/basic-auth`.

### Added

- Support for PostgreSQL 9.4+ as Kong's primary datastore. [#331](https://github.com/Mashape/kong/issues/331) [#1054](https://github.com/Mashape/kong/issues/1054)
- Configurable Cassandra reading/writing consistency. [#1026](https://github.com/Mashape/kong/pull/1026)
- Admin API: including pending and running timers count in the response to `/`. [#992](https://github.com/Mashape/kong/pull/992)
- Plugins
  - **New correlation-id plugin**: assign unique identifiers to the requests processed by Kong. Courtesy of [@opyate](https://github.com/opyate). [#1094](https://github.com/Mashape/kong/pull/1094)
  - LDAP: add support for LDAP authentication. [#1133](https://github.com/Mashape/kong/pull/1133)
  - StatsD: add support for StatsD logging. [#1142](https://github.com/Mashape/kong/pull/1142)
  - JWT: add support for RS256 signed tokens thanks to [@kdstew](https://github.com/kdstew)! [#1053](https://github.com/Mashape/kong/pull/1053)
  - ACL: appends `X-Consumer-Groups` to the request, so the upstream service can check what groups the consumer belongs to. [#1154](https://github.com/Mashape/kong/pull/1154)
  - Galileo (mashape-analytics): increase batch sending timeout to 30s. [#1091](https://github.com/Mashape/kong/pull/1091)
- Added `ttl_on_failure` option in the cluster configuration, to configure the TTL of failed nodes. [#1125](https://github.com/Mashape/kong/pull/1125)

### Fixed

- Introduce a new `port` option when connecting to your Cassandra cluster instead of using the CQL default (9042). [#1139](https://github.com/Mashape/kong/issues/1139)
- Plugins
  - Request/Response Transformer: add missing migrations for upgrades from ` <= 0.5.x`. [#1064](https://github.com/Mashape/kong/issues/1064)
  - OAuth2
    - Error responses comply to RFC 6749. [#1017](https://github.com/Mashape/kong/issues/1017)
    - Handle multipart requests. [#1067](https://github.com/Mashape/kong/issues/1067)
    - Make access_tokens correctly expire. [#1089](https://github.com/Mashape/kong/issues/1089)

> **internal**
> - replace globals with singleton pattern thanks to [@mars](https://github.com/mars).
> - fixed resolution mismatches when using deep paths in the path resolver thanks to [siddharthkchatterjee](https://github.com/siddharthkchatterjee)

## [0.7.0] - 2016/02/24

### Breaking changes

Due to the NGINX security fixes (CVE-2016-0742, CVE-2016-0746, CVE-2016-0747), OpenResty was bumped to `1.9.7.3` which is not backwards compatible, and thus requires changes to be made to the `nginx` property of Kong's configuration file. See the [0.7 upgrade path](https://github.com/Mashape/kong/blob/master/UPGRADE.md#upgrade-to-07x) for instructions.

However by upgrading the underlying OpenResty version, source installations do not have to patch the NGINX core and use the old `ssl-cert-by-lua` branch of ngx_lua anymore. This will make source installations much easier.

### Added

- Support for OpenResty `1.9.7.*`. This includes NGINX security fixes (CVE-2016-0742, CVE-2016-0746, CVE-2016-0747). [#906](https://github.com/Mashape/kong/pull/906)
- Plugins
  - **New Runscope plugin**: Monitor your APIs from Kong with Runscope. Courtesy of [@mansilladev](https://github.com/mansilladev). [#924](https://github.com/Mashape/kong/pull/924)
  - Datadog: New `response.size` metric. [#923](https://github.com/Mashape/kong/pull/923)
  - Rate-Limiting and Response Rate-Limiting
    - New `config.async` option to asynchronously increment counters to reduce latency at the cost of slighly reducing the accuracy. [#912](https://github.com/Mashape/kong/pull/912)
    - New `config.continue_on_error` option to keep proxying requests in case the datastore is unreachable. rate-limiting operations will be disabled until the datastore is responsive again. [#953](https://github.com/Mashape/kong/pull/953)
- CLI
  - Perform a simple permission check on the NGINX working directory when starting, to prevent errors during execution. [#939](https://github.com/Mashape/kong/pull/939)
- Send 50x errors with the appropriate format. [#927](https://github.com/Mashape/kong/pull/927) [#970](https://github.com/Mashape/kong/pull/970)

### Fixed

- Plugins
  - OAuth2
    - Better handling of `redirect_uri` (prevent the use of fragments and correctly handle querystrings). Courtesy of [@PGBI](https://github.com/PGBI). [#930](https://github.com/Mashape/kong/pull/930)
    - Add `PUT` support to the `/auth2_tokens` route. [#897](https://github.com/Mashape/kong/pull/897)
    - Better error message when the `access_token` is missing. [#1003](https://github.com/Mashape/kong/pull/1003)
  - IP restriction: Fix an issue that could arise when restarting Kong. Now Kong does not need to be restarted for the ip-restriction configuration to take effect. [#782](https://github.com/Mashape/kong/pull/782) [#960](https://github.com/Mashape/kong/pull/960)
  - ACL: Properly invalidating entities when assigning a new ACL group. [#996](https://github.com/Mashape/kong/pull/996)
  - SSL: Replace shelled out openssl calls with native `ngx.ssl` conversion utilities, which preserve the certificate chain. [#968](https://github.com/Mashape/kong/pull/968)
- Avoid user warning on start when the user is not root. [#964](https://github.com/Mashape/kong/pull/964)
- Store Serf logs in NGINX working directory to prevent eventual permission issues. [#975](https://github.com/Mashape/kong/pull/975)
- Allow plugins configured on a Consumer *without* being configured on an API to run. [#978](https://github.com/Mashape/kong/issues/978) [#980](https://github.com/Mashape/kong/pull/980)
- Fixed an edge-case where Kong nodes would not be registered in the `nodes` table. [#1008](https://github.com/Mashape/kong/pull/1008)

## [0.6.1] - 2016/02/03

This release contains tiny bug fixes that were especially annoying for complex Cassandra setups and power users of the Admin API!

### Added

- A `timeout` property for the Cassandra configuration. In ms, this timeout is effective as a connection and a reading timeout. [#937](https://github.com/Mashape/kong/pull/937)

### Fixed

- Correctly set the Cassandra SSL certificate in the Nginx configuration while starting Kong. [#921](https://github.com/Mashape/kong/pull/921)
- Rename the `user` Cassandra property to `username` (Kong looks for `username`, hence `user` would fail). [#922](https://github.com/Mashape/kong/pull/922)
- Allow Cassandra authentication with arbitrary plain text auth providers (such as Instaclustr uses), fixing authentication with them. [#937](https://github.com/Mashape/kong/pull/937)
- Admin API
  - Fix the `/plugins/:id` route for `PATCH` method. [#941](https://github.com/Mashape/kong/pull/941)
- Plugins
  - HTTP logging: remove the additional `\r\n` at the end of the logging request body. [#926](https://github.com/Mashape/kong/pull/926)
  - Galileo: catch occasional internal errors happening when a request was cancelled by the client and fix missing shm for the retry policy. [#931](https://github.com/Mashape/kong/pull/931)

## [0.6.0] - 2016/01/22

### Breaking changes

 We would recommended to consult the suggested [0.6 upgrade path](https://github.com/Mashape/kong/blob/master/UPGRADE.md#upgrade-to-06x) for this release.

- [Serf](https://www.serfdom.io) is now a Kong dependency. It allows Kong nodes to communicate between each other opening the way to many features and improvements.
- The configuration file changed. Some properties were renamed, others were moved, and some are new. We would recommended checking out the new default configuration file.
- Drop the Lua 5.1 dependency which was only used by the CLI. The CLI now runs with LuaJIT, which is consistent with other Kong components (Luarocks and OpenResty) already relying on LuaJIT. Make sure the LuaJIT interpreter is included in your `$PATH`. [#799](https://github.com/Mashape/kong/pull/799)

### Added

One of the biggest new features of this release is the cluster-awareness added to Kong in [#729](https://github.com/Mashape/kong/pull/729), which deserves its own section:

- Each Kong node is now aware of belonging to a cluster through Serf. Nodes automatically join the specified cluster according to the configuration file's settings.
- The datastore cache is not invalidated by expiration time anymore, but following an invalidation strategy between the nodes of a same cluster, leading to improved performance.
- Admin API
  - Expose a `/cache` endpoint for retrieving elements stored in the in-memory cache of a node.
  - Expose a `/cluster` endpoint used to add/remove/list members of the cluster, and also used internally for data propagation.
- CLI
  - New `kong cluster` command for cluster management.
  - New `kong status` command for cluster healthcheck.

Other additions include:

- New Cassandra driver which makes Kong aware of the Cassandra cluster. Kong is now unaffected if one of your Cassandra nodes goes down as long as a replica is available on another node. Load balancing policies also improve the performance along with many other smaller improvements. [#803](https://github.com/Mashape/kong/pull/803)
- Admin API
  - A new `total` field in API responses, that counts the total number of entities in the datastore. [#635](https://github.com/Mashape/kong/pull/635)
- Configuration
  - Possibility to configure the keyspace replication strategy for Cassandra. It will be taken into account by the migrations when the configured keyspace does not already exist. [#350](https://github.com/Mashape/kong/issues/350)
  - Dnsmasq is now optional. You can specify a custom DNS resolver address that Kong will use when resolving hostnames. This can be configured in `kong.yml`. [#625](https://github.com/Mashape/kong/pull/625)
- Plugins
  - **New "syslog" plugin**: send logs to local sytem log. [#698](https://github.com/Mashape/kong/pull/698)
  - **New "loggly" plugin**: send logs to Loggly over UDP. [#698](https://github.com/Mashape/kong/pull/698)
  - **New "datadog" plugin**: send logs to Datadog server. [#758](https://github.com/Mashape/kong/pull/758)
  - OAuth2
    - Add support for `X-Forwarded-Proto` header. [#650](https://github.com/Mashape/kong/pull/650)
    - Expose a new `/oauth2_tokens` endpoint with the possibility to retrieve, update or delete OAuth 2.0 access tokens. [#729](https://github.com/Mashape/kong/pull/729)
  - JWT
    - Support for base64 encoded secrets. [#838](https://github.com/Mashape/kong/pull/838) [#577](https://github.com/Mashape/kong/issues/577)
    - Support to configure the claim in which the key is given into the token (not `iss` only anymore). [#838](https://github.com/Mashape/kong/pull/838)
  - Request transformer
    - Support for more transformation options: `remove`, `replace`, `add`, `append` motivated by [#393](https://github.com/Mashape/kong/pull/393). See [#824](https://github.com/Mashape/kong/pull/824)
    - Support JSON body transformation. [#569](https://github.com/Mashape/kong/issues/569)
  - Response transformer
    - Support for more transformation options: `remove`, `replace`, `add`, `append` motivated by [#393](https://github.com/Mashape/kong/pull/393). See [#822](https://github.com/Mashape/kong/pull/822)

### Changed

- As mentioned in the breaking changes section, a new configuration file format and validation. All properties are now documented and commented out with their default values. This allows for a lighter configuration file and more clarity as to what properties relate to. It also catches configuration mistakes. [#633](https://github.com/Mashape/kong/pull/633)
- Replace the UUID generator library with a new implementation wrapping lib-uuid, fixing eventual conflicts happening in cases such as described in [#659](https://github.com/Mashape/kong/pull/659). See [#695](https://github.com/Mashape/kong/pull/695)
- Admin API
  - Increase the maximum body size to 10MB in order to handle configuration requests with heavy payloads. [#700](https://github.com/Mashape/kong/pull/700)
  - Disable access logs for the `/status` endpoint.
  - The `/status` endpoint now includes `database` statistics, while the previous stats have been moved to a `server` response field. [#635](https://github.com/Mashape/kong/pull/635)

### Fixed

- Behaviors described in [#603](https://github.com/Mashape/kong/issues/603) related to the failure of Cassandra nodes thanks to the new driver. [#803](https://github.com/Mashape/kong/issues/803)
- Latency headers are now properly included in responses sent to the client. [#708](https://github.com/Mashape/kong/pull/708)
- `strip_request_path` does not add a trailing slash to the API's `upstream_url` anymore before proxying. [#675](https://github.com/Mashape/kong/issues/675)
- Do not URL decode querystring before proxying the request to the upstream service. [#749](https://github.com/Mashape/kong/issues/749)
- Handle cases when the request would be terminated prior to the Kong execution (that is, before ngx_lua reaches the `access_by_lua` context) in cases such as the use of a custom nginx module. [#594](https://github.com/Mashape/kong/issues/594)
- Admin API
  - The PUT method now correctly updates boolean fields (such as `strip_request_path`). [#765](https://github.com/Mashape/kong/pull/765)
  - The PUT method now correctly resets a plugin configuration. [#720](https://github.com/Mashape/kong/pull/720)
  - PATCH correctly set previously unset fields. [#861](https://github.com/Mashape/kong/pull/861)
  - In the responses, the `next` link is not being displayed anymore if there are no more entities to be returned. [#635](https://github.com/Mashape/kong/pull/635)
  - Prevent the update of `created_at` fields. [#820](https://github.com/Mashape/kong/pull/820)
  - Better `request_path` validation for APIs. "/" is not considered a valid path anymore. [#881](https://github.com/Mashape/kong/pull/881)
- Plugins
  - Galileo: ensure the `mimeType` value is always a string in ALFs. [#584](https://github.com/Mashape/kong/issues/584)
  - JWT: allow to update JWT credentials using the PATCH method. It previously used to reply with `405 Method not allowed` because the PATCH method was not implemented. [#667](https://github.com/Mashape/kong/pull/667)
  - Rate limiting: fix a warning when many periods are configured. [#681](https://github.com/Mashape/kong/issues/681)
  - Basic Authentication: do not re-hash the password field when updating a credential. [#726](https://github.com/Mashape/kong/issues/726)
  - File log: better permissions for on file creation for file-log plugin. [#877](https://github.com/Mashape/kong/pull/877)
  - OAuth2
    - Implement correct responses when the OAuth2 challenges are refused. [#737](https://github.com/Mashape/kong/issues/737)
    - Handle querystring on `/authorize` and `/token` URLs. [#687](https://github.com/Mashape/kong/pull/667)
    - Handle punctuation in scopes on `/authorize` and `/token` endpoints. [#658](https://github.com/Mashape/kong/issues/658)

> ***internal***
> - Event bus for local and cluster-wide events propagation. Plans for this event bus is to be widely used among Kong in the future.
> - The Kong Public Lua API (Lua helpers integrated in Kong such as DAO and Admin API helpers) is now documented with [ldoc](http://stevedonovan.github.io/ldoc/) format and published on [the online documentation](https://getkong.org/docs/latest/lua-reference/).
> - Work has been done to restore the reliability of the CI platforms.
> - Migrations can now execute DML queries (instead of DDL queries only). Handy for migrations implying plugin configuration changes, plugins renamings etc... [#770](https://github.com/Mashape/kong/pull/770)

## [0.5.4] - 2015/12/03

### Fixed

- Mashape Analytics plugin (renamed Galileo):
  - Improve stability under heavy load. [#757](https://github.com/Mashape/kong/issues/757)
  - base64 encode ALF request/response bodies, enabling proper support for Galileo bodies inspection capabilities. [#747](https://github.com/Mashape/kong/pull/747)
  - Do not include JSON bodies in ALF `postData.params` field. [#766](https://github.com/Mashape/kong/pull/766)

## [0.5.3] - 2015/11/16

### Fixed

- Avoids additional URL encoding when proxying to an upstream service. [#691](https://github.com/Mashape/kong/pull/691)
- Potential timing comparison bug in HMAC plugin. [#704](https://github.com/Mashape/kong/pull/704)

### Added

- The Galileo plugin now supports arbitrary host, port and path values. [#721](https://github.com/Mashape/kong/pull/721)

## [0.5.2] - 2015/10/21

A few fixes requested by the community!

### Fixed

- Kong properly search the `nginx` in your $PATH variable.
- Plugins:
  - OAuth2: can detect that the originating protocol for a request was HTTPS through the `X-Forwarded-Proto` header and work behind another reverse proxy (load balancer). [#650](https://github.com/Mashape/kong/pull/650)
  - HMAC signature: support for `X-Date` header to sign the request for usage in browsers (since the `Date` header is protected). [#641](https://github.com/Mashape/kong/issues/641)

## [0.5.1] - 2015/10/13

Fixing a few glitches we let out with 0.5.0!

### Added

- Basic Authentication and HMAC Authentication plugins now also send the `X-Credential-Username` to the upstream server.
- Admin API now accept JSON when receiving a CORS request. [#580](https://github.com/Mashape/kong/pull/580)
- Add a `WWW-Authenticate` header for HTTP 401 responses for basic-auth and key-auth. [#588](https://github.com/Mashape/kong/pull/588)

### Changed

- Protect Kong from POODLE SSL attacks by omitting SSLv3 (CVE-2014-3566). [#563](https://github.com/Mashape/kong/pull/563)
- Remove support for key-auth key in body. [#566](https://github.com/Mashape/kong/pull/566)

### Fixed

- Plugins
  - HMAC
    - The migration for this plugin is now correctly being run. [#611](https://github.com/Mashape/kong/pull/611)
    - Wrong username doesn't return HTTP 500 anymore, but 403. [#602](https://github.com/Mashape/kong/pull/602)
  - JWT: `iss` not being found doesn't return HTTP 500 anymore, but 403. [#578](https://github.com/Mashape/kong/pull/578)
  - OAuth2: client credentials flow does not include a refresh token anymore. [#562](https://github.com/Mashape/kong/issues/562)
- Fix an occasional error when updating a plugin without a config. [#571](https://github.com/Mashape/kong/pull/571)

## [0.5.0] - 2015/09/25

With new plugins, many improvements and bug fixes, this release comes with breaking changes that will require your attention.

### Breaking changes

Several breaking changes are introduced. You will have to slightly change your configuration file and a migration script will take care of updating your database cluster. **Please follow the instructions in [UPDATE.md](/UPDATE.md#update-to-kong-050) for an update without downtime**.

- Many plugins were renamed due to new naming conventions for consistency. [#480](https://github.com/Mashape/kong/issues/480)
- In the configuration file, the Cassandra `hosts` property was renamed to `contact_points`. [#513](https://github.com/Mashape/kong/issues/513)
- Properties belonging to APIs entities have been renamed for clarity. [#513](https://github.com/Mashape/kong/issues/513)
  - `public_dns` -> `request_host`
  - `path` -> `request_path`
  - `strip_path` -> `strip_request_path`
  - `target_url` -> `upstream_url`
- `plugins_configurations` have been renamed to `plugins`, and their `value` property has been renamed to `config` to avoid confusions. [#513](https://github.com/Mashape/kong/issues/513)
- The database schema has been updated to handle the separation of plugins outside of the core repository.
- The Key authentication and Basic authentication plugins routes have changed:

```
Old route                             New route
/consumers/:consumer/keyauth       -> /consumers/:consumer/key-auth
/consumers/:consumer/keyauth/:id   -> /consumers/:consumer/key-auth/:id
/consumers/:consumer/basicauth     -> /consumers/:consumer/basic-auth
/consumers/:consumer/basicauth/:id -> /consumers/:consumer/basic-auth/:id
```

The old routes are still maintained but will be removed in upcoming versions. Consider them **deprecated**.

- Admin API
  - The route to retrieve enabled plugins is now under `/plugins/enabled`.
  - The route to retrieve a plugin's configuration schema is now under `/plugins/schema/{plugin name}`.

#### Added

- Plugins
  - **New Response Rate Limiting plugin**: Give a usage quota to your users based on a parameter in your response. [#247](https://github.com/Mashape/kong/pull/247)
  - **New ACL (Access Control) plugin**: Configure authorizations for your Consumers. [#225](https://github.com/Mashape/kong/issues/225)
  - **New JWT (JSON Web Token) plugin**: Verify and authenticate JWTs. [#519](https://github.com/Mashape/kong/issues/519)
  - **New HMAC signature plugin**: Verify and authenticate HMAC signed HTTP requests. [#549](https://github.com/Mashape/kong/pull/549)
  - Plugins migrations. Each plugin can now have its own migration scripts if it needs to store data in your cluster. This is a step forward to improve Kong's pluggable architecture. [#443](https://github.com/Mashape/kong/pull/443)
  - Basic Authentication: the password field is now sha1 encrypted. [#33](https://github.com/Mashape/kong/issues/33)
  - Basic Authentication: now supports credentials in the `Proxy-Authorization` header. [#460](https://github.com/Mashape/kong/issues/460)

#### Changed

- Basic Authentication and Key Authentication now require authentication parameters even when the `Expect: 100-continue` header is being sent. [#408](https://github.com/Mashape/kong/issues/408)
- Key Auth plugin does not support passing the key in the request payload anymore. [#566](https://github.com/Mashape/kong/pull/566)
- APIs' names cannot contain characters from the RFC 3986 reserved list. [#589](https://github.com/Mashape/kong/pull/589)

#### Fixed

- Resolver
  - Making a request with a querystring will now correctly match an API's path. [#496](https://github.com/Mashape/kong/pull/496)
- Admin API
  - Data associated to a given API/Consumer will correctly be deleted if related Consumer/API is deleted. [#107](https://github.com/Mashape/kong/issues/107) [#438](https://github.com/Mashape/kong/issues/438) [#504](https://github.com/Mashape/kong/issues/504)
  - The `/api/{api_name_or_id}/plugins/{plugin_name_or_id}` changed to `/api/{api_name_or_id}/plugins/{plugin_id}` to avoid requesting the wrong plugin if two are configured for one API. [#482](https://github.com/Mashape/kong/pull/482)
  - APIs created without a `name` but with a `request_path` will now have a name which defaults to the set `request_path`. [#547](https://github.com/Mashape/kong/issues/547)
- Plugins
  - Mashape Analytics: More robust buffer and better error logging. [#471](https://github.com/Mashape/kong/pull/471)
  - Mashape Analytics: Several ALF (API Log Format) serialization fixes. [#515](https://github.com/Mashape/kong/pull/515)
  - Oauth2: A response is now returned on `http://kong:8001/consumers/{consumer}/oauth2/{oauth2_id}`. [#469](https://github.com/Mashape/kong/issues/469)
  - Oauth2: Saving `authenticated_userid` on Password Grant. [#476](https://github.com/Mashape/kong/pull/476)
  - Oauth2: Proper handling of the `/oauth2/authorize` and `/oauth2/token` endpoints in the OAuth 2.0 Plugin when an API with a `path` is being consumed using the `public_dns` instead. [#503](https://github.com/Mashape/kong/issues/503)
  - OAuth2: Properly returning `X-Authenticated-UserId` in the `client_credentials` and `password` flows. [#535](https://github.com/Mashape/kong/issues/535)
  - Response-Transformer: Properly handling JSON responses that have a charset specified in their `Content-Type` header.

## [0.4.2] - 2015/08/10

#### Added

- Cassandra authentication and SSL encryption. [#405](https://github.com/Mashape/kong/pull/405)
- `preserve_host` flag on APIs to preserve the Host header when a request is proxied. [#444](https://github.com/Mashape/kong/issues/444)
- Added the Resource Owner Password Credentials Grant to the OAuth 2.0 Plugin. [#448](https://github.com/Mashape/kong/issues/448)
- Auto-generation of default SSL certificate. [#453](https://github.com/Mashape/kong/issues/453)

#### Changed

- Remove `cassandra.port` property in configuration. Ports are specified by having `cassandra.hosts` addresses using the `host:port` notation (RFC 3986). [#457](https://github.com/Mashape/kong/pull/457)
- Default SSL certificate is now auto-generated and stored in the `nginx_working_dir`.
- OAuth 2.0 plugin now properly forces HTTPS.

#### Fixed

- Better handling of multi-nodes Cassandra clusters. [#450](https://github.com/Mashape/kong/pull/405)
- mashape-analytics plugin: handling of numerical values in querystrings. [#449](https://github.com/Mashape/kong/pull/405)
- Path resolver `strip_path` option wrongfully matching the `path` property multiple times in the request URI. [#442](https://github.com/Mashape/kong/issues/442)
- File Log Plugin bug that prevented the file creation in some environments. [#461](https://github.com/Mashape/kong/issues/461)
- Clean output of the Kong CLI. [#235](https://github.com/Mashape/kong/issues/235)

## [0.4.1] - 2015/07/23

#### Fixed

- Issues with the Mashape Analytics plugin. [#425](https://github.com/Mashape/kong/pull/425)
- Handle hyphens when executing path routing with `strip_path` option enabled. [#431](https://github.com/Mashape/kong/pull/431)
- Adding the Client Credentials OAuth 2.0 flow. [#430](https://github.com/Mashape/kong/issues/430)
- A bug that prevented "dnsmasq" from being started on some systems, including Debian. [f7da790](https://github.com/Mashape/kong/commit/f7da79057ce29c7d1f6d90f4bc160cc3d9c8611f)
- File Log plugin: optimizations by avoiding the buffered I/O layer. [20bb478](https://github.com/Mashape/kong/commit/20bb478952846faefec6091905bd852db24a0289)

## [0.4.0] - 2015/07/15

#### Added

- Implement wildcard subdomains for APIs' `public_dns`. [#381](https://github.com/Mashape/kong/pull/381) [#297](https://github.com/Mashape/kong/pull/297)
- Plugins
  - **New OAuth 2.0 plugin.** [#341](https://github.com/Mashape/kong/pull/341) [#169](https://github.com/Mashape/kong/pull/169)
  - **New Mashape Analyics plugin.** [#360](https://github.com/Mashape/kong/pull/360) [#272](https://github.com/Mashape/kong/pull/272)
  - **New IP whitelisting/blacklisting plugin.** [#379](https://github.com/Mashape/kong/pull/379)
  - Ratelimiting: support for multiple limits. [#382](https://github.com/Mashape/kong/pull/382) [#205](https://github.com/Mashape/kong/pull/205)
  - HTTP logging: support for HTTPS endpoint. [#342](https://github.com/Mashape/kong/issues/342)
  - Logging plugins: new properties for logs timing. [#351](https://github.com/Mashape/kong/issues/351)
  - Key authentication: now auto-generates a key if none is specified. [#48](https://github.com/Mashape/kong/pull/48)
- Resolver
  - `path` property now accepts arbitrary depth. [#310](https://github.com/Mashape/kong/issues/310)
- Admin API
  - Enable CORS by default. [#371](https://github.com/Mashape/kong/pull/371)
  - Expose a new endpoint to get a plugin configuration's schema. [#376](https://github.com/Mashape/kong/pull/376) [#309](https://github.com/Mashape/kong/pull/309)
  - Expose a new endpoint to retrieve a node's status. [417c137](https://github.com/Mashape/kong/commit/417c1376c08d3562bebe0c0816c6b54df045f515)
- CLI
  - `$ kong migrations reset` now asks for confirmation. [#365](https://github.com/Mashape/kong/pull/365)

#### Fixed

- Plugins
  - Basic authentication not being executed if added to an API with default configuration. [6d732cd](https://github.com/Mashape/kong/commit/6d732cd8b0ec92ef328faa843215d8264f50fb75)
  - SSL plugin configuration parsing. [#353](https://github.com/Mashape/kong/pull/353)
  - SSL plugin doesn't accept a `consumer_id` anymore, as this wouldn't make sense. [#372](https://github.com/Mashape/kong/pull/372) [#322](https://github.com/Mashape/kong/pull/322)
  - Authentication plugins now return `401` when missing credentials. [#375](https://github.com/Mashape/kong/pull/375) [#354](https://github.com/Mashape/kong/pull/354)
- Admin API
  - Non supported HTTP methods now return `405` instead of `500`. [38f1b7f](https://github.com/Mashape/kong/commit/38f1b7fa9f45f60c4130ef5ff9fe2c850a2ba586)
  - Prevent PATCH requests from overriding a plugin's configuration if partially updated. [9a7388d](https://github.com/Mashape/kong/commit/9a7388d695c9de105917cde23a684a7d6722a3ca)
- Handle occasionally missing `schema_migrations` table. [#365](https://github.com/Mashape/kong/pull/365) [#250](https://github.com/Mashape/kong/pull/250)

> **internal**
> - DAO:
>   - Complete refactor. No more need for hard-coded queries. [#346](https://github.com/Mashape/kong/pull/346)
> - Schemas:
>   - New `self_check` test for schema definitions. [5bfa7ca](https://github.com/Mashape/kong/commit/5bfa7ca13561173161781f872244d1340e4152c1)

## [0.3.2] - 2015/06/08

#### Fixed

- Uppercase Cassandra keyspace bug that prevented Kong to work with [kongdb.org](http://kongdb.org/)
- Multipart requests not properly parsed in the admin API. [#344](https://github.com/Mashape/kong/issues/344)

## [0.3.1] - 2015/06/07

#### Fixed

- Schema migrations are now automatic, which was missing from previous releases. [#303](https://github.com/Mashape/kong/issues/303)

## [0.3.0] - 2015/06/04

#### Added

- Support for SSL.
- Plugins
  - New HTTP logging plugin. [#226](https://github.com/Mashape/kong/issues/226) [#251](https://github.com/Mashape/kong/pull/251)
  - New SSL plugin.
  - New request size limiting plugin. [#292](https://github.com/Mashape/kong/pull/292)
  - Default logging format improvements. [#226](https://github.com/Mashape/kong/issues/226) [#262](https://github.com/Mashape/kong/issues/262)
  - File logging now logs to a custom file. [#202](https://github.com/Mashape/kong/issues/202)
  - Keyauth plugin now defaults `key_names` to "apikey".
- Admin API
  - RESTful routing. Much nicer Admin API routing. Ex: `/apis/{name_or_id}/plugins`. [#98](https://github.com/Mashape/kong/issues/98) [#257](https://github.com/Mashape/kong/pull/257)
  - Support `PUT` method for endpoints such as `/apis/`, `/apis/plugins/`, `/consumers/`
  - Support for `application/json` and `x-www-form-urlencoded` Content Types for all `PUT`, `POST` and `PATCH` endpoints by passing a `Content-Type` header. [#236](https://github.com/Mashape/kong/pull/236)
- Resolver
  - Support resolving APIs by Path as well as by Header. [#192](https://github.com/Mashape/kong/pull/192) [#282](https://github.com/Mashape/kong/pull/282)
  - Support for `X-Host-Override` as an alternative to `Host` for browsers. [#203](https://github.com/Mashape/kong/issues/203) [#246](https://github.com/Mashape/kong/pull/246)
- Auth plugins now send user informations to your upstream services. [#228](https://github.com/Mashape/kong/issues/228)
- Invalid `target_url` value are now being catched when creating an API. [#149](https://github.com/Mashape/kong/issues/149)

#### Fixed

- Uppercase Cassandra keyspace causing migration failure. [#249](https://github.com/Mashape/kong/issues/249)
- Guarantee that ratelimiting won't allow requests in case the atomicity of the counter update is not guaranteed. [#289](https://github.com/Mashape/kong/issues/289)

> **internal**
> - Schemas:
>   - New property type: `array`. [#277](https://github.com/Mashape/kong/pull/277)
>   - Entities schemas now live in their own files and are starting to be unit tested.
>   - Subfields are handled better: (notify required subfields and auto-vivify is subfield has default values).
> - Way faster unit tests. Not resetting the DB anymore between tests.
> - Improved coverage computation (exclude `vendor/`).
> - Travis now lints `kong/`.
> - Way faster Travis setup.
> - Added a new HTTP client for in-nginx usage, using the cosocket API.
> - Various refactorings.
> - Fix [#196](https://github.com/Mashape/kong/issues/196).
> - Disabled ipv6 in resolver.

## [0.2.1] - 2015/05/12

This is a maintenance release including several bug fixes and usability improvements.

#### Added
- Support for local DNS resolution. [#194](https://github.com/Mashape/kong/pull/194)
- Support for Debian 8 and Ubuntu 15.04.
- DAO
  - Cassandra version bumped to 2.1.5
  - Support for Cassandra downtime. If Cassandra goes down and is brought back up, Kong will not need to restart anymore, statements will be re-prepared on-the-fly. This is part of an ongoing effort from [jbochi/lua-resty-cassandra#47](https://github.com/jbochi/lua-resty-cassandra/pull/47), [#146](https://github.com/Mashape/kong/pull/146) and [#187](https://github.com/Mashape/kong/pull/187).
Queries effectued during the downtime will still be lost. [#11](https://github.com/Mashape/kong/pull/11)
  - Leverage reused sockets. If the DAO reuses a socket, it will not re-set their keyspace. This should give a small but appreciable performance improvement. [#170](https://github.com/Mashape/kong/pull/170)
  - Cascade delete plugins configurations when deleting a Consumer or an API associated with it. [#107](https://github.com/Mashape/kong/pull/107)
  - Allow Cassandra hosts listening on different ports than the default. [#185](https://github.com/Mashape/kong/pull/185)
- CLI
  - Added a notice log when Kong tries to connect to Cassandra to avoid user confusion. [#168](https://github.com/Mashape/kong/pull/168)
  - The CLI now tests if the ports are already being used before starting and warns.
- Admin API
  - `name` is now an optional property for APIs. If none is being specified, the name will be the API `public_dns`. [#181](https://github.com/Mashape/kong/pull/181)
- Configuration
  - The memory cache size is now configurable. [#208](https://github.com/Mashape/kong/pull/208)

#### Fixed
- Resolver
  - More explicit "API not found" message from the resolver if the Host was not found in the system. "Api not foun with Host: %s".
  - If multiple hosts headers are being sent, Kong will test them all to see if one of the API is in the system. [#186](https://github.com/Mashape/kong/pull/186)
- Admin API: responses now have a new line after the body. [#164](https://github.com/Mashape/kong/issues/164)
- DAO: keepalive property is now properly passed when Kong calls `set_keepalive` on Cassandra sockets.
- Multipart dependency throwing error at startup. [#213](https://github.com/Mashape/kong/pull/213)

> **internal**
> - Separate Migrations from the DAO factory.
> - Update dev config + Makefile rules (`run` becomes `start`).
> - Introducing an `ngx` stub for unit tests and CLI.
> - Switch many PCRE regexes to using patterns.

## [0.2.0-2] - 2015/04/27

First public release of Kong. This version brings a lot of internal improvements as well as more usability and a few additional plugins.

#### Added
- Plugins
  - CORS plugin.
  - Request transformation plugin.
  - NGINX plus monitoring plugin.
- Configuration
  - New properties: `proxy_port` and `api_admin_port`. [#142](https://github.com/Mashape/kong/issues/142)
- CLI
  - Better info, help and error messages. [#118](https://github.com/Mashape/kong/issues/118) [#124](https://github.com/Mashape/kong/issues/124)
  - New commands: `kong reload`, `kong quit`. [#114](https://github.com/Mashape/kong/issues/114) Alias of `version`: `kong --version` [#119](https://github.com/Mashape/kong/issues/119)
  - `kong restart` simply starts Kong if not previously running + better pid file handling. [#131](https://github.com/Mashape/kong/issues/131)
- Package distributions: .rpm, .deb and .pkg for easy installs on most common platforms.

#### Fixed
- Admin API: trailing slash is not necessary anymore for core ressources such as `/apis` or `/consumers`.
- Leaner default configuration. [#156](https://github.com/Mashape/kong/issues/156)

> **internal**
> - All scripts moved to the CLI as "hidden" commands (`kong db`, `kong config`).
> - More tests as always, and they are structured better. The coverage went down mainly because of plugins which will later move to their own repos. We are all eagerly waiting for that!
> - `src/` was renamed to `kong/` for ease of development
> - All system dependencies versions for package building and travis-ci are now listed in `versions.sh`
> - DAO doesn't need to `:prepare()` prior to run queries. Queries can be prepared at runtime. [#146](https://github.com/Mashape/kong/issues/146)

## [0.1.1beta-2] - 2015/03/30

#### Fixed

- Wrong behaviour of auto-migration in `kong start`.

## [0.1.0beta-3] - 2015/03/25

First public beta. Includes caching and better usability.

#### Added
- Required Openresty is now `1.7.10.1`.
- Freshly built CLI, rewritten in Lua
- `kong start` using a new DB keyspace will automatically migrate the schema. [#68](https://github.com/Mashape/kong/issues/68)
- Anonymous error reporting on Proxy and API. [#64](https://github.com/Mashape/kong/issues/64)
- Configuration
  - Simplified configuration file (unified in `kong.yml`).
  - In configuration, `plugins_installed` was renamed to `plugins_available`. [#59](https://github.com/Mashape/kong/issues/59)
  - Order of `plugins_available` doesn't matter anymore. [#17](https://github.com/Mashape/kong/issues/17)
  - Better handling of plugins: Kong now detects which plugins are configured and if they are installed on the current machine.
  - `bin/kong` now defaults on `/etc/kong.yml` for config and `/var/logs/kong` for output. [#71](https://github.com/Mashape/kong/issues/71)
- Proxy: APIs/Consumers caching with expiration for faster authentication.
- Admin API: Plugins now use plain form parameters for configuration. [#70](https://github.com/Mashape/kong/issues/70)
- Keep track of already executed migrations. `rollback` now behaves as expected. [#8](https://github.com/Mashape/kong/issues/8)

#### Fixed
- `Server` header now sends Kong. [#57](https://github.com/Mashape/kong/issues/57)
- migrations not being executed in order on Linux. This issue wasn't noticed until unit testing the migrations because for now we only have 1 migration file.
- Admin API: Errors responses are now sent as JSON. [#58](https://github.com/Mashape/kong/issues/58)

> **internal**
> - We now have code linting and coverage.
> - Faker and Migrations instances don't live in the DAO Factory anymore, they are only used in scripts and tests.
> - `scripts/config.lua` allows environment based configurations. `make dev` generates a `kong.DEVELOPMENT.yml` and `kong_TEST.yml`. Different keyspaces and ports.
> - `spec_helpers.lua` allows tests to not rely on the `Makefile` anymore. Integration tests can run 100% from `busted`.
> - Switch integration testing from [httpbin.org] to [mockbin.com].
> - `core` plugin was renamed to `resolver`.

## [0.0.1alpha-1] - 2015/02/25

First version running with Cassandra.

#### Added
- Basic proxying.
- Built-in authentication plugin (api key, HTTP basic).
- Built-in ratelimiting plugin.
- Built-in TCP logging plugin.
- Configuration API (for consumers, apis, plugins).
- CLI `bin/kong` script.
- Database migrations (using `db.lua`).

[unreleased]: https://github.com/mashape/kong/compare/0.9.9...next
[0.9.9]: https://github.com/mashape/kong/compare/0.9.8...0.9.9
[0.9.8]: https://github.com/mashape/kong/compare/0.9.7...0.9.8
[0.9.7]: https://github.com/mashape/kong/compare/0.9.6...0.9.7
[0.9.6]: https://github.com/mashape/kong/compare/0.9.5...0.9.6
[0.9.5]: https://github.com/mashape/kong/compare/0.9.4...0.9.5
[0.9.4]: https://github.com/mashape/kong/compare/0.9.3...0.9.4
[0.9.3]: https://github.com/mashape/kong/compare/0.9.2...0.9.3
[0.9.2]: https://github.com/mashape/kong/compare/0.9.1...0.9.2
[0.9.1]: https://github.com/mashape/kong/compare/0.9.0...0.9.1
[0.9.0]: https://github.com/mashape/kong/compare/0.8.3...0.9.0
[0.8.3]: https://github.com/mashape/kong/compare/0.8.2...0.8.3
[0.8.2]: https://github.com/mashape/kong/compare/0.8.1...0.8.2
[0.8.1]: https://github.com/mashape/kong/compare/0.8.0...0.8.1
[0.8.0]: https://github.com/mashape/kong/compare/0.7.0...0.8.0
[0.7.0]: https://github.com/mashape/kong/compare/0.6.1...0.7.0
[0.6.1]: https://github.com/mashape/kong/compare/0.6.0...0.6.1
[0.6.0]: https://github.com/mashape/kong/compare/0.5.4...0.6.0
[0.5.4]: https://github.com/mashape/kong/compare/0.5.3...0.5.4
[0.5.3]: https://github.com/mashape/kong/compare/0.5.2...0.5.3
[0.5.2]: https://github.com/mashape/kong/compare/0.5.1...0.5.2
[0.5.1]: https://github.com/mashape/kong/compare/0.5.0...0.5.1
[0.5.0]: https://github.com/mashape/kong/compare/0.4.2...0.5.0
[0.4.2]: https://github.com/mashape/kong/compare/0.4.1...0.4.2
[0.4.1]: https://github.com/mashape/kong/compare/0.4.0...0.4.1
[0.4.0]: https://github.com/mashape/kong/compare/0.3.2...0.4.0
[0.3.2]: https://github.com/mashape/kong/compare/0.3.1...0.3.2
[0.3.1]: https://github.com/mashape/kong/compare/0.3.0...0.3.1
[0.3.0]: https://github.com/mashape/kong/compare/0.2.1...0.3.0
[0.2.1]: https://github.com/mashape/kong/compare/0.2.0-2...0.2.1
[0.2.0-2]: https://github.com/mashape/kong/compare/0.1.1beta-2...0.2.0-2
[0.1.1beta-2]: https://github.com/mashape/kong/compare/0.1.0beta-3...0.1.1beta-2
[0.1.0beta-3]: https://github.com/mashape/kong/compare/2236374d5624ad98ea21340ca685f7584ec35744...0.1.0beta-3
[0.0.1alpha-1]: https://github.com/mashape/kong/compare/ffd70b3101ba38d9acc776038d124f6e2fccac3c...2236374d5624ad98ea21340ca685f7584ec35744
