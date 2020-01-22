# Table of Contents


- [2.0.0](#200)
- [1.5.0](#150)
- [1.4.3](#143)
- [1.4.2](#142)
- [1.4.1](#141)
- [1.4.0](#140)
- [1.3.0](#130)
- [1.2.2](#122)
- [1.2.1](#121)
- [1.2.0](#120)
- [1.1.2](#112)
- [1.1.1](#111)
- [1.1.0](#110)
- [1.0.3](#103)
- [1.0.2](#102)
- [1.0.1](#101)
- [1.0.0](#100)
- [0.15.0](#0150)
- [0.14.1](#0141)
- [0.14.0](#0140---20180705)
- [0.13.1](#0131---20180423)
- [0.13.0](#0130---20180322)
- [0.12.3](#0123---20180312)
- [0.12.2](#0122---20180228)
- [0.12.1](#0121---20180118)
- [0.12.0](#0120---20180116)
- [0.11.2](#0112---20171129)
- [0.11.1](#0111---20171024)
- [0.10.4](#0104---20171024)
- [0.11.0](#0110---20170816)
- [0.10.3](#0103---20170524)
- [0.10.2](#0102---20170501)
- [0.10.1](#0101---20170327)
- [0.10.0](#0100---20170307)
- [0.9.9 and prior](#099---20170202)


## [2.0.0]

> Released 2020/01/20

This is a new major release of Kong, including new features such as **Hybrid
mode**, **Go language support for plugins** and **buffered proxying**, and
much more.

Kong 2.0.0 removes the deprecated service mesh functionality, which was
been retired in favor of [Kuma](https://kuma.io), as Kong continues to
focus on its core gateway capabilities.

Please note that Kong 2.0.0 also removes support for migrating from versions
below 1.0.0. If you are running Kong 0.x versions below 0.14.1, you need to
migrate to 0.14.1 first, and once you are running 0.14.1, you can migrate to
Kong 1.5.0, which includes special provisions for migrating from Kong 0.x,
such as the `kong migrations migrate-apis` command, and then finally to Kong
2.0.0.

### Dependencies

- :warning: The required OpenResty version is
  [1.15.8.2](http://openresty.org/en/changelog-1015008.html), and the
  the set of patches included has changed, including the latest release of
  [lua-kong-nginx-module](https://github.com/Kong/lua-kong-nginx-module).
  If you are installing Kong from one of our distribution
  packages, you are not affected by this change.

**Note:** if you are not using one of our distribution packages and compiling
OpenResty from source, you must still apply Kong's [OpenResty
patches](https://github.com/Kong/kong-build-tools/tree/master/openresty-build-tools/openresty-patches)
(and, as highlighted above, compile OpenResty with the new
lua-kong-nginx-module). Our [kong-build-tools](https://github.com/Kong/kong-build-tools)
repository will allow you to do both easily.

### Packaging

- RPM packages are now signed with our own GPG keys. You can download our public
  key at https://bintray.com/user/downloadSubjectPublicKey?username=kong
- Kong now ships with a systemd unit file

### Additions

##### Core

  - :fireworks: **Hybrid mode** for management of control-plane and
    data-plane nodes. This allows running control-plane nodes using a
    database and have them deliver configuration updates to DB-less
    data-plane nodes.
    [#5294](https://github.com/Kong/kong/pull/5294)
  - :fireworks: **Buffered proxying** - plugins can now request buffered
    reading of the service response (as opposed to the streaming default),
    allowing them to modify headers based on the contents of the body
    [#5234](https://github.com/Kong/kong/pull/5234)
  - The `transformations` in DAO schemas now also support `on_read`,
    allowing for two-way (read/write) data transformations between
    Admin API input/output and database storage.
    [#5100](https://github.com/Kong/kong/pull/5100)
  - Added `threshold` attribute for health checks
    [#5206](https://github.com/Kong/kong/pull/5206)
  - Caches for core entities and plugin-controlled entities (such as
    credentials, etc.) are now separated, protecting the core entities
    from cache eviction caused by plugin behavior.
    [#5114](https://github.com/Kong/kong/pull/5114)
  - Cipher suite was updated to the Mozilla v5 release.
    [#5342](https://github.com/Kong/kong/pull/5342)
  - Better support for using already existing Cassandra keyspaces
    when migrating
    [#5361](https://github.com/Kong/kong/pull/5361)
  - Better log messages when plugin modules fail to load
    [#5357](https://github.com/Kong/kong/pull/5357)
  - `stream_listen` now supports the `backlog` option.
    [#5346](https://github.com/Kong/kong/pull/5346)
  - The internal cache was split into two independent segments,
    `kong.core_cache` and `kong.cache`. The `core_cache` region is
    used by the Kong core to store configuration data that doesn't
    change often. The other region is used to store plugin
    runtime data that is dependent on traffic pattern and user
    behavior. This change should decrease the cache contention
    between Kong core and plugins and result in better performance
    overall.
    - :warning: Note that both structures rely on the already existent
      `mem_cache_size` configuration option to set their size,
      so when upgrading from a previous Kong version, the cache
      memory consumption might double if this value is not adjusted
      [#5114](https://github.com/Kong/kong/pull/5114)

##### CLI

  - `kong config init` now accepts a filename argument
    [#4451](https://github.com/Kong/kong/pull/4451)

##### Configuration

  - :fireworks: **Extended support for Nginx directive injections**
    via Kong configurations, reducing the needs for custom Nginx
    templates. New injection contexts were added: `nginx_main_`,
    `nginx_events` and `nginx_supstream_` (`upstream` in `stream`
    mode).
    [#5390](https://github.com/Kong/kong/pull/5390)
  - Enable `reuseport` option in the listen directive by default
    and allow specifying both `reuseport` and `backlog=N` in the
    listener flags.
    [#5332](https://github.com/Kong/kong/pull/5332)
  - Check existence of `lua_ssl_trusted_certificate` at startup
    [#5345](https://github.com/Kong/kong/pull/5345)

##### Admin API

  - Added `/upstreams/<id>/health?balancer_health=1` attribute for
    detailed information about balancer health based on health
    threshold configuration
    [#5206](https://github.com/Kong/kong/pull/5206)

##### PDK

  - New functions `kong.service.request.enable_buffering`,
    `kong.service.response.get_raw_body` and
    `kong.service.response.get_body` for use with buffered proxying
    [#5315](https://github.com/Kong/kong/pull/5315)

##### Plugins

  - :fireworks: **Go plugin support** - plugins can now be written in
    Go as well as Lua, through the use of an out-of-process Go plugin server.
    [#5326](https://github.com/Kong/kong/pull/5326)
  - The lifecycle of the Plugin Server daemon for Go language support is
    managed by Kong itself.
    [#5366](https://github.com/Kong/kong/pull/5366)
  - :fireworks: **New plugin: ACME** - Let's Encrypt and ACMEv2 integration with Kong
    [#5333](https://github.com/Kong/kong/pull/5333)
  - :fireworks: aws-lambda: bumped version to 3.0.1, with a number of new features!
    [#5083](https://github.com/Kong/kong/pull/5083)
  - :fireworks: prometheus: bumped to version 0.7.0 including major performance improvements
    [#5295](https://github.com/Kong/kong/pull/5295)
  - zipkin: bumped to version 0.2.1
    [#5239](https://github.com/Kong/kong/pull/5239)
  - session: bumped to version 2.2.0, adding `authenticated_groups` support
    [#5108](https://github.com/Kong/kong/pull/5108)
  - rate-limiting: added experimental support for standardized headers based on the
    ongoing [RFC draft](https://tools.ietf.org/html/draft-polli-ratelimit-headers-01)
    [#5335](https://github.com/Kong/kong/pull/5335)
  - rate-limiting: added Retry-After header on HTTP 429 responses
    [#5329](https://github.com/Kong/kong/pull/5329)
  - datadog: report metrics with tags --
    Thanks [mvanholsteijn](https://github.com/mvanholsteijn) for the patch!
    [#5154](https://github.com/Kong/kong/pull/5154)
  - request-size-limiting: added `size_unit` configuration option.
    [#5214](https://github.com/Kong/kong/pull/5214)
  - request-termination: add extra check for `conf.message` before sending
    response back with body object included.
    [#5202](https://github.com/Kong/kong/pull/5202)
  - jwt: add `X-Credential-Identifier` header in response --
    Thanks [davinwang](https://github.com/davinwang) for the patch!
    [#4993](https://github.com/Kong/kong/pull/4993)

### Fixes

##### Core

  - Correct detection of update upon deleting Targets --
    Thanks [pyrl247](https://github.com/pyrl247) for the patch!
  - Fix declarative config loading of entities with abstract records
    [#5343](https://github.com/Kong/kong/pull/5343)
  - Fix sort priority when matching routes by longest prefix
    [#5430](https://github.com/Kong/kong/pull/5430)
  - Detect changes in Routes that happen halfway through a router update
    [#5431](https://github.com/Kong/kong/pull/5431)

##### Admin API

  - Corrected the behavior when overwriting a Service configuration using
    the `url` shorthand
    [#5315](https://github.com/Kong/kong/pull/5315)

##### Core

  - :warning: **Removed Service Mesh support** - That has been deprecated in
    Kong 1.4 and made off-by-default already, and the code is now gone in 2.0.
    For Service Mesh, we now have [Kuma](https://kuma.io), which is something
    designed for Mesh patterns from day one, so we feel at peace with removing
    Kong's native Service Mesh functionality and focus on its core capabilities
    as a gateway.

##### Configuration

  - Routes using `tls` are now supported in stream mode by adding an
    entry in `stream_listen` with the `ssl` keyword enabled.
    [#5346](https://github.com/Kong/kong/pull/5346)
  - As part of service mesh removal, serviceless proxying was removed.
    You can still set `service = null` when creating a route for use with
    serverless plugins such as `aws-lambda`, or `request-termination`.
    [#5353](https://github.com/Kong/kong/pull/5353)
  - Removed the `origins` property which was used for service mesh.
    [#5351](https://github.com/Kong/kong/pull/5351)
  - Removed the `transparent` property which was used for service mesh.
    [#5350](https://github.com/Kong/kong/pull/5350)
  - Removed the `nginx_optimizations` property; the equivalent settings
    can be performed via Nginx directive injections.
    [#5390](https://github.com/Kong/kong/pull/5390)
  - The Nginx directive injection prefixes `nginx_http_upstream_`
    and `nginx_http_status_` were renamed to `nginx_upstream_` and
    `nginx_status_` respectively.
    [#5390](https://github.com/Kong/kong/pull/5390)

##### Plugins

  - Removed the Sidecar Injector plugin which was used for service mesh.
    [#5199](https://github.com/Kong/kong/pull/5199)


[Back to TOC](#table-of-contents)


## [1.5.0]

> Released 2020/01/20

Kong 1.5.0 is the last release in the Kong 1.x series, and it was designed to
help Kong 0.x users upgrade out of that series and into more current releases.
Kong 1.5.0 includes two features designed to ease the transition process: the
new `kong migrations migrate-apis` commands, to help users migrate away from
old `apis` entities which were deprecated in Kong 0.13.0 and removed in Kong
1.0.0, and a compatibility flag to provide better router compatibility across
Kong versions.

### Additions

##### Core

  - New `path_handling` attribute in Routes entities, which selects the behavior
    the router will have when combining the Service Path, the Route Path, and
    the Request path into a single path sent to the upstream. This attribute
    accepts two values, `v0` or `v1`, making the router behave as in Kong 0.x or
    Kong 1.x, respectively. [#5360](https://github.com/Kong/kong/pull/5360)

##### CLI

  - New command `kong migrations migrate-apis`, which converts any existing
    `apis` from an old Kong 0.x installation and generates Route, Service and
    Plugin entities with equivalent configurations. The converted routes are
    set to use `path_handling = v0`, to ensure compatibility.
    [#5176](https://github.com/Kong/kong/pull/5176)

### Fixes

##### Core

  - Fixed the routing prioritization that could lead to a match in a lower
    priority path. [#5443](https://github.com/Kong/kong/pull/5443)
  - Changes in router or plugins entities while the rebuild is in progress now
    are treated in the next rebuild, avoiding to build invalid iterators.
    [#5431](https://github.com/Kong/kong/pull/5431)
  - Fixed invalid incorrect calculation of certificate validity period.
    [#5449](https://github.com/Kong/kong/pull/5449) -- Thanks
    [Bevisy](https://github.com/Bevisy) for the patch!


[Back to TOC](#table-of-contents)


## [1.4.3]

> Released 2020/01/09

:warning: This release includes a security fix to address potentially
sensitive information being written to the error log file. This affects
certain uses of the Admin API for DB-less mode, described below.

This is a patch release in the 1.4 series, and as such, strictly contains
bugfixes. There are no new features nor breaking changes.

### Fixes

##### Core

  - Fix the detection of the need for balancer updates
    when deleting targets
    [#5352](https://github.com/kong/kong/issues/5352) --
    Thanks [zeeshen](https://github.com/zeeshen) for the patch!
  - Fix behavior of longest-path criteria when matching routes
    [#5383](https://github.com/kong/kong/issues/5383)
  - Fix incorrect use of cache when using header-based routing
    [#5267](https://github.com/kong/kong/issues/5267) --
    Thanks [marlonfan](https://github.com/marlonfan) for the patch!

##### Admin API

  - Do not make a debugging dump of the declarative config input into
    `error.log` when posting it with `/config` and using `_format_version`
    as a top-level parameter (instead of embedded in the `config` parameter).
    [#5411](https://github.com/kong/kong/issues/5411)
  - Fix incorrect behavior of PUT for /certificates
    [#5321](https://github.com/kong/kong/issues/5321)

##### Plugins

  - acl: fixed an issue where getting ACLs by group failed when multiple
    consumers share the same group
    [#5322](https://github.com/kong/kong/issues/5322)


[Back to TOC](#table-of-contents)


## [1.4.2]

> Released 2019/12/10

This is another patch release in the 1.4 series, and as such, strictly
contains bugfixes. There are no new features nor breaking changes.

### Fixes

##### Core

  - Fixes some corner cases in the balancer behavior
    [#5318](https://github.com/Kong/kong/pull/5318)

##### Plugins

  - http-log: disable queueing when using the default
    settings, to avoid memory consumption issues
    [#5323](https://github.com/Kong/kong/pull/5323)
  - prometheus: restore compatibility with version 0.6.0
    [#5303](https://github.com/Kong/kong/pull/5303)


[Back to TOC](#table-of-contents)


## [1.4.1]

> Released 2019/12/03

This is a patch release in the 1.4 series, and as such, strictly contains
bugfixes. There are no new features nor breaking changes.

### Fixes

##### Core

  - Fixed a memory leak in the balancer
    [#5229](https://github.com/Kong/kong/pull/5229) --
    Thanks [zeeshen](https://github.com/zeeshen) for the patch!
  - Removed arbitrary limit on worker connections.
    [#5148](https://github.com/Kong/kong/pull/5148)
  - Fixed `preserve_host` behavior for gRPC routes
    [#5225](https://github.com/Kong/kong/pull/5225)
  - Fix migrations for ttl for OAuth2 tokens
    [#5253](https://github.com/Kong/kong/pull/5253)
  - Improve handling of errors when creating balancers
    [#5284](https://github.com/Kong/kong/pull/5284)

##### CLI

  - Fixed an issue with `kong config db_export` when reading
    entities that are ttl-enabled and whose ttl value is `null`.
    [#5185](https://github.com/Kong/kong/pull/5185)

##### Admin API

  - Various fixes for Admin API behavior
    [#5174](https://github.com/Kong/kong/pull/5174),
    [#5178](https://github.com/Kong/kong/pull/5178),
    [#5191](https://github.com/Kong/kong/pull/5191),
    [#5186](https://github.com/Kong/kong/pull/5186)

##### Plugins

  - http-log: do not impose a retry delay on successful sends
    [#5282](https://github.com/Kong/kong/pull/5282)


[Back to TOC](#table-of-contents)

## [1.4.0]

> Released on 2019/10/22

### Installation

  - :warning: All Bintray assets have been renamed from `.all.` / `.noarch.` to be
    architecture specific namely `.arm64.` and `.amd64.`

### Additions

##### Core

  - :fireworks: New configuration option `cassandra_refresh_frequency` to set
    the frequency that Kong will check for Cassandra cluster topology changes,
    avoiding restarts when Cassandra nodes are added or removed.
    [#5071](https://github.com/Kong/kong/pull/5071)
  - New `transformations` property in DAO schemas, which allows adding functions
    that run when database rows are inserted or updated.
    [#5047](https://github.com/Kong/kong/pull/5047)
  - The new attribute `hostname` has been added to `upstreams` entities. This
    attribute is used as the `Host` header when proxying requests through Kong
    to servers that are listening on server names that are different from the
    names to which they resolve.
    [#4959](https://github.com/Kong/kong/pull/4959)
  - New status interface has been introduced. It exposes insensitive health,
    metrics and error read-only information from Kong, which can be consumed by
    other services in the infrastructure to monitor Kong's health.
    This removes the requirement of the long-used workaround to monitor Kong's
    health by injecting a custom server block.
    [#4977](https://github.com/Kong/kong/pull/4977)
  - New Admin API response header `X-Kong-Admin-Latency`, reporting the time
    taken by Kong to process an Admin API request.
    [#4966](https://github.com/Kong/kong/pull/4996/files)

##### Configuration

  - :warning: New configuration option `service_mesh` which enables or disables
    the Service Mesh functionality. The Service Mesh is being deprecated and
    will not be available in the next releases of Kong.
    [#5124](https://github.com/Kong/kong/pull/5124)
  - New configuration option `router_update_frequency` that allows setting the
    frequency that router and plugins will be checked for changes. This new
    option avoids performance degradation when Kong routes or plugins are
    frequently changed. [#4897](https://github.com/Kong/kong/pull/4897)

##### Plugins

  - rate-limiting: in addition to consumer, credential, and IP levels, now
    rate-limiting plugin has service-level support. Thanks
    [wuguangkuo](https://github.com/wuguangkuo) for the patch!
    [#5031](https://github.com/Kong/kong/pull/5031)
  - Now rate-limiting `local` policy counters expire using the shared
    dictionary's TTL, avoiding to keep unnecessary counters in memory. Thanks
    [cb372](https://github.com/cb372) for the patch!
    [#5029](https://github.com/Kong/kong/pull/5029)
  - Authentication plugins have support for tags now.
    [#4945](https://github.com/Kong/kong/pull/4945)
  - response-transformer plugin now supports renaming response headers. Thanks
    [aalmazanarbs](https://github.com/aalmazanarbs) for the patch!
    [#5040](https://github.com/Kong/kong/pull/5040)

### Fixes

##### Core

  - :warning: Service Mesh is known to cause HTTPS requests to upstream to
    ignore `proxy_ssl*` directives, so it is being discontinued in the next
    major release of Kong. In this release it is disabled by default, avoiding
    this issue, and it can be enabled as aforementioned in the configuration
    section. [#5124](https://github.com/Kong/kong/pull/5124)
  - Fixed an issue on reporting the proper request method and URL arguments on
    NGINX-produced errors in logging plugins.
    [#5073](https://github.com/Kong/kong/pull/5073)
  - Fixed an issue where targets were not properly updated in all Kong workers
    when they were removed. [#5041](https://github.com/Kong/kong/pull/5041)
  - Deadlocks cases in database access functions when using Postgres and
    cleaning up `cluster_events` in high-changing scenarios were fixed.
    [#5118](https://github.com/Kong/kong/pull/5118)
  - Fixed issues with tag-filtered GETs on Cassandra-backed nodes.
    [#5105](https://github.com/Kong/kong/pull/5105)

##### Configuration

  - Fixed Lua parsing and error handling in declarative configurations.
    [#5019](https://github.com/Kong/kong/pull/5019)
  - Automatically escape any unescaped `#` characters in parsed `KONG_*`
    environment variables. [#5062](https://github.com/Kong/kong/pull/5062)

##### Plugins

  - file-log: creates log file with proper permissions when Kong uses
    declarative config. [#5028](https://github.com/Kong/kong/pull/5028)
  - basic-auth: fixed credentials parsing when using DB-less
    configurations. [#5080](https://github.com/Kong/kong/pull/5080)
  - jwt: plugin handles empty claims and return the correct error message.
    [#5123](https://github.com/Kong/kong/pull/5123)
    Thanks to [@jeremyjpj0916](https://github.com/jeremyjpj0916) for the patch!
  - serverless-functions: Lua code in declarative configurations is validated
    and loaded correctly.
    [#24](https://github.com/Kong/kong-plugin-serverless-functions/pull/24)
  - request-transformer: fixed bug on removing and then adding request headers
    with the same name.
    [#9](https://github.com/Kong/kong-plugin-request-transformer/pull/9)


[Back to TOC](#table-of-contents)

## [1.3.0]

> Released on 2019/08/21

Kong 1.3 is the first version to officially support **gRPC proxying**!

Following our vision for Kong to proxy modern Web services protocols, we are
excited for this newest addition to the family of protocols already supported
by Kong (HTTP(s), WebSockets, and TCP). As we have recently stated in our
latest [Community Call](https://konghq.com/community-call/), more protocols are
to be expected in the future.

Additionally, this release includes several highly-requested features such as
support for upstream **mutual TLS**, **header-based routing** (not only
`Host`), **database export**, and **configurable upstream keepalive
timeouts**.

### Changes

##### Dependencies

- :warning: The required OpenResty version has been bumped to
  [1.15.8.1](http://openresty.org/en/changelog-1015008.html). If you are
  installing Kong from one of our distribution packages, you are not affected
  by this change. See [#4382](https://github.com/Kong/kong/pull/4382).
  With this new version comes a number of improvements:
  1. The new [ngx\_http\_grpc\_module](https://nginx.org/en/docs/http/ngx_http_grpc_module.html).
  2. Configurable of upstream keepalive connections by timeout or number of
     requests.
  3. Support for ARM64 architectures.
  4. LuaJIT GC64 mode for x86_64 architectures, raising the LuaJIT GC-managed
     memory limit from 2GB to 128TB and producing more predictable GC
     performance.
- :warning: From this version on, the new
  [lua-kong-nginx-module](https://github.com/Kong/lua-kong-nginx-module) Nginx
  module is **required** to be built into OpenResty for Kong to function
  properly. This new module allows Kong to support new features such as mutual
  TLS authentication. If you are installing Kong from one of our distribution
  packages, you are not affected by this change.
  [openresty-build-tools#26](https://github.com/Kong/openresty-build-tools/pull/26)

**Note:** if you are not using one of our distribution packages and compiling
OpenResty from source, you must still apply Kong's [OpenResty
patches](https://github.com/kong/openresty-patches) (and, as highlighted above,
compile OpenResty with the new lua-kong-nginx-module). Our new
[openresty-build-tools](https://github.com/Kong/openresty-build-tools)
repository will allow you to do both easily.

##### Core

- :warning: Bugfixes in the router *may, in some edge-cases*, result in
  different Routes being matched. It was reported to us that the router behaved
  incorrectly in some cases when configuring wildcard Hosts and regex paths
  (e.g. [#3094](https://github.com/Kong/kong/issues/3094)). It may be so that
  you are subject to these bugs without realizing it. Please ensure that
  wildcard Hosts and regex paths Routes you have configured are matching as
  expected before upgrading.
  See [9ca4dc0](https://github.com/Kong/kong/commit/9ca4dc09fdb12b340531be8e0f9d1560c48664d5),
  [2683b86](https://github.com/Kong/kong/commit/2683b86c2f7680238e3fe85da224d6f077e3425d), and
  [6a03e1b](https://github.com/Kong/kong/commit/6a03e1bd95594716167ccac840ff3e892ed66215)
  for details.
- Upstream connections are now only kept-alive for 100 requests or 60 seconds
  (idle) by default. Previously, upstream connections were not actively closed
  by Kong. This is a (non-breaking) change in behavior, inherited from Nginx
  1.15, and configurable via new configuration properties (see below).

##### Configuration

- :warning: The `upstream_keepalive` configuration property is deprecated, and
  replaced by the new `nginx_http_upstream_keepalive` property. Its behavior is
  almost identical, but the notable difference is that the latter leverages the
  [injected Nginx
  directives](https://konghq.com/blog/kong-ce-nginx-injected-directives/)
  feature added in Kong 0.14.0.
  In future releases, we will gradually increase support for injected Nginx
  directives. We have high hopes that this will remove the occasional need for
  custom Nginx configuration templates.
  [#4382](https://github.com/Kong/kong/pull/4382)

### Additions

##### Core

- :fireworks: **Native gRPC proxying.** Two new protocol types; `grpc` and
  `grpcs` correspond to gRPC over h2c and gRPC over h2. They can be specified
  on a Route or a Service's `protocol` attribute (e.g. `protocol = grpcs`).
  When an incoming HTTP/2 request matches a Route with a `grpc(s)` protocol,
  the request will be handled by the
  [ngx\_http\_grpc\_module](https://nginx.org/en/docs/http/ngx_http_grpc_module.html),
  and proxied to the upstream Service according to the gRPC protocol
  specifications.  :warning: Note that not all Kong plugins are compatible with
  gRPC requests yet.  [#4801](https://github.com/Kong/kong/pull/4801)
- :fireworks: **Mutual TLS** handshake with upstream services. The Service
  entity now has a new `client_certificate` attribute, which is a foreign key
  to a Certificate entity. If specified, Kong will use the Certificate as a
  client TLS cert during the upstream TLS handshake.
  [#4800](https://github.com/Kong/kong/pull/4800)
- :fireworks: **Route by any request header**. The router now has the ability
  to match Routes by any request header (not only `Host`). The Route entity now
  has a new `headers` attribute, which is a map of headers names and values.
  E.g. `{ "X-Forwarded-Host": ["example.org"], "Version": ["2", "3"] }`.
  [#4758](https://github.com/Kong/kong/pull/4758)
- :fireworks: **Least-connection load-balancing**. A new `algorithm` attribute
  has been added to the Upstream entity. It can be set to `"round-robin"`
  (default), `"consistent-hashing"`, or `"least-connections"`.
  [#4528](https://github.com/Kong/kong/pull/4528)
- A new core entity, "CA Certificates" has been introduced and can be accessed
  via the new `/ca_certificates` Admin API endpoint. CA Certificates entities
  will be used as CA trust store by Kong. Certificates stored by this entity
  need not include their private key.
  [#4798](https://github.com/Kong/kong/pull/4798)
- Healthchecks now use the combination of IP + Port + Hostname when storing
  upstream health information. Previously, only IP + Port were used. This means
  that different virtual hosts served behind the same IP/port will be treated
  differently with regards to their health status. New endpoints were added to
  the Admin API to manually set a Target's health status.
  [#4792](https://github.com/Kong/kong/pull/4792)

##### Configuration

- :fireworks: A new section in the `kong.conf` file describes [injected Nginx
  directives](https://konghq.com/blog/kong-ce-nginx-injected-directives/)
  (added to Kong 0.14.0) and specifies a few default ones.
  In future releases, we will gradually increase support for injected Nginx
  directives. We have high hopes that this will remove the occasional need for
  custom Nginx configuration templates.
  [#4382](https://github.com/Kong/kong/pull/4382)
- :fireworks: New configuration properties allow for controlling the behavior of
  upstream keepalive connections. `nginx_http_upstream_keepalive_requests` and
  `nginx_http_upstream_keepalive_timeout` respectively control the maximum
  number of proxied requests and idle timeout of an upstream connection.
  [#4382](https://github.com/Kong/kong/pull/4382)
- New flags have been added to the `*_listen` properties: `deferred`, `bind`,
  and `reuseport`.
  [#4692](https://github.com/Kong/kong/pull/4692)

##### CLI

- :fireworks: **Database export** via the new `kong config db_export` CLI
  command. This command will export the configuration present in the database
  Kong is connected to (Postgres or Cassandra) as a YAML file following Kong's
  declarative configuration syntax. This file can thus be imported later on
  in a DB-less Kong node or in another database via `kong config db_import`.
  [#4809](https://github.com/Kong/kong/pull/4809)

##### Admin API

- Many endpoints now support more levels of nesting for ease of access.
  For example: `/services/:services/routes/:routes` is now a valid API
  endpoint.
  [#4713](https://github.com/Kong/kong/pull/4713)
- The API now accepts `form-urlencoded` payloads with deeply nested data
  structures. Previously, it was only possible to send such data structures
  via JSON payloads.
  [#4768](https://github.com/Kong/kong/pull/4768)

##### Plugins

- :fireworks: **New bundled plugin**: the [session
  plugin](https://github.com/Kong/kong-plugin-session) is now bundled in Kong.
  It can be used to manage browser sessions for APIs proxied and authenticated
  by Kong.
  [#4685](https://github.com/Kong/kong/pull/4685)
- ldap-auth: A new `config.ldaps` property allows configuring the plugin to
  connect to the LDAP server via TLS. It provides LDAPS support instead of only
  relying on STARTTLS.
  [#4743](https://github.com/Kong/kong/pull/4743)
- jwt-auth: The new `header_names` property accepts an array of header names
  the JWT plugin should inspect when authenticating a request. It defaults to
  `["Authorization"]`.
  [#4757](https://github.com/Kong/kong/pull/4757)
- [azure-functions](https://github.com/Kong/kong-plugin-azure-functions):
  Bumped to 0.4 for minor fixes and performance improvements.
- [kubernetes-sidecar-injector](https://github.com/Kong/kubernetes-sidecar-injector):
  The plugin is now more resilient to Kubernetes schema changes.
- [serverless-functions](https://github.com/Kong/kong-plugin-serverless-functions):
    - Bumped to 0.3 for minor performance improvements.
    - Functions can now have upvalues.
- [prometheus](https://github.com/Kong/kong-plugin-prometheus): Bumped to
  0.4.1 for minor performance improvements.
- cors: add OPTIONS, TRACE and CONNECT to default allowed methods
  [#4899](https://github.com/Kong/kong/pull/4899)
  Thanks to [@eshepelyuk](https://github.com/eshepelyuk) for the patch!

##### PDK

- New function `kong.service.set_tls_cert_key()`. This functions sets the
  client TLS certificate used while handshaking with the upstream service.
  [#4797](https://github.com/Kong/kong/pull/4797)

### Fixes

##### Core

- Fix WebSocket protocol upgrades in some cases due to case-sensitive
  comparisons of the `Upgrade` header.
  [#4780](https://github.com/Kong/kong/pull/4780)
- Router: Fixed a bug causing invalid matches when configuring two or more
  Routes with a plain `hosts` attribute shadowing another Route's wildcard
  `hosts` attribute. Details of the issue can be seen in
  [01b1cb8](https://github.com/Kong/kong/pull/4775/commits/01b1cb871b1d84e5e93c5605665b68c2f38f5a31).
  [#4775](https://github.com/Kong/kong/pull/4775)
- Router: Ensure regex paths always have priority over plain paths. Details of
  the issue can be seen in
  [2683b86](https://github.com/Kong/kong/commit/2683b86c2f7680238e3fe85da224d6f077e3425d).
  [#4775](https://github.com/Kong/kong/pull/4775)
- Cleanup of expired rows in PostgreSQL is now much more efficient thanks to a
  new query plan.
  [#4716](https://github.com/Kong/kong/pull/4716)
- Improved various query plans against Cassandra instances by increasing the
  default page size.
  [#4770](https://github.com/Kong/kong/pull/4770)

##### Plugins

- cors: ensure non-preflight OPTIONS requests can be proxied.
  [#4899](https://github.com/Kong/kong/pull/4899)
  Thanks to [@eshepelyuk](https://github.com/eshepelyuk) for the patch!
- Consumer references in various plugin entities are now
  properly marked as required, avoiding credentials that map to no Consumer.
  [#4879](https://github.com/Kong/kong/pull/4879)
- hmac-auth: Correct the encoding of HTTP/1.0 requests.
  [#4839](https://github.com/Kong/kong/pull/4839)
- oauth2: empty client_id wasn't checked, causing a server error.
  [#4884](https://github.com/Kong/kong/pull/4884)
- response-transformer: preserve empty arrays correctly.
  [#4901](https://github.com/Kong/kong/pull/4901)

##### CLI

- Fixed an issue when running `kong restart` and Kong was not running,
  causing stdout/stderr logging to turn off.
  [#4772](https://github.com/Kong/kong/pull/4772)

##### Admin API

- Ensure PUT works correctly when applied to plugin configurations.
  [#4882](https://github.com/Kong/kong/pull/4882)

##### PDK

- Prevent PDK calls from failing in custom content blocks.
  This fixes a misbehavior affecting the Prometheus plugin.
  [#4904](https://github.com/Kong/kong/pull/4904)
- Ensure `kong.response.add_header` works in the `rewrite` phase.
  [#4888](https://github.com/Kong/kong/pull/4888)

[Back to TOC](#table-of-contents)

## [1.2.2]

> Released on 2019/08/14

:warning: This release includes patches to the NGINX core (1.13.6) fixing
vulnerabilities in the HTTP/2 module (CVE-2019-9511 CVE-2019-9513
CVE-2019-9516).

This is a patch release in the 1.2 series, and as such, strictly contains
bugfixes. There are no new features nor breaking changes.

### Fixes

##### Core

- Case sensitivity fix when clearing the Upgrade header.
  [#4779](https://github.com/kong/kong/issues/4779)

### Performance

##### Core

- Speed up cascade deletes in Cassandra.
  [#4770](https://github.com/kong/kong/pull/4770)

## [1.2.1]

> Released on 2019/06/26

This is a patch release in the 1.2 series, and as such, strictly contains
bugfixes. There are no new features nor breaking changes.

### Fixes

##### Core

- Fix an issue preventing WebSocket connections from being established by
  clients. This issue was introduced in Kong 1.1.2, and would incorrectly clear
  the `Upgrade` response header.
  [#4719](https://github.com/Kong/kong/pull/4719)
- Fix a memory usage growth issue in the `/config` endpoint when configuring
  Upstream entities. This issue was mostly observed by users of the [Kong
  Ingress Controller](https://github.com/Kong/kubernetes-ingress-controller).
  [#4733](https://github.com/Kong/kong/pull/4733)
- Cassandra: ensure serial consistency is `LOCAL_SERIAL` when a
  datacenter-aware load balancing policy is in use. This fixes unavailability
  exceptions sometimes experienced when connecting to a multi-datacenter
  cluster with cross-datacenter connectivity issues.
  [#4734](https://github.com/Kong/kong/pull/4734)
- Schemas: fix an issue in the schema validator that would not allow specifying
  `false` in some schema rules, such a `{ type = "boolean", eq = false }`.
  [#4708](https://github.com/Kong/kong/pull/4708)
  [#4727](https://github.com/Kong/kong/pull/4727)
- Fix an underlying issue with regards to database entities cache keys
  generation.
  [#4717](https://github.com/Kong/kong/pull/4717)

##### Configuration

- Ensure the `cassandra_local_datacenter` configuration property is specified
  when a datacenter-aware Cassandra load balancing policy is in use.
  [#4734](https://github.com/Kong/kong/pull/4734)

##### Plugins

- request-transformer: fix an issue that would prevent adding a body to
  requests without one.
  [Kong/kong-plugin-request-transformer#4](https://github.com/Kong/kong-plugin-request-transformer/pull/4)
- kubernetes-sidecar-injector: fix an issue causing mutating webhook calls to
  fail.
  [Kong/kubernetes-sidecar-injector#9](https://github.com/Kong/kubernetes-sidecar-injector/pull/9)

[Back to TOC](#table-of-contents)

## [1.2.0]

> Released on: 2019/06/07

This release brings **improvements to reduce long latency tails**,
**consolidates declarative configuration support**, and comes with **newly open
sourced plugins** previously only available to Enterprise customers. It also
ships with new features improving observability and usability.

This release includes database migrations. Please take a few minutes to read
the [1.2 Upgrade Path](https://github.com/Kong/kong/blob/master/UPGRADE.md)
for more details regarding changes and migrations before planning to upgrade
your Kong cluster.

### Installation

- :warning: All Bintray repositories have been renamed from
  `kong-community-edition-*` to `kong-*`.
- :warning: All Kong packages have been renamed from `kong-community-edition`
  to `kong`.

For more details about the updated installation, please visit the official docs:
[https://konghq.com/install](https://konghq.com/install/).

### Additions

##### Core

- :fireworks: Support for **wildcard SNI matching**: the
  `ssl_certificate_by_lua` phase and the stream `preread` phase) is now able to
  match a client hello SNI against any registered wildcard SNI. This is
  particularly helpful for deployments serving a certificate for multiple
  subdomains.
  [#4457](https://github.com/Kong/kong/pull/4457)
- :fireworks: **HTTPS Routes can now be matched by SNI**: the `snis` Route
  attribute (previously only available for `tls` Routes) can now be set for
  `https` Routes and is evaluated by the HTTP router.
  [#4633](https://github.com/Kong/kong/pull/4633)
- :fireworks: **Native support for HTTPS redirects**: Routes have a new
  `https_redirect_status_code` attribute specifying the status code to send
  back to the client if a plain text request was sent to an `https` Route.
  [#4424](https://github.com/Kong/kong/pull/4424)
- The loading of declarative configuration is now done atomically, and with a
  safety check to verify that the new configuration fits in memory.
  [#4579](https://github.com/Kong/kong/pull/4579)
- Schema fields can now be marked as immutable.
  [#4381](https://github.com/Kong/kong/pull/4381)
- Support for loading custom DAO strategies from plugins.
  [#4518](https://github.com/Kong/kong/pull/4518)
- Support for IPv6 to `tcp` and `tls` Routes.
  [#4333](https://github.com/Kong/kong/pull/4333)

##### Configuration

- :fireworks: **Asynchronous router updates**: a new configuration property
  `router_consistency` accepts two possible values: `strict` and `eventual`.
  The former is the default setting and makes router rebuilds highly
  consistent between Nginx workers. It can result in long tail latency if
  frequent Routes and Services updates are expected. The latter helps
  preventing long tail latency issues by instructing Kong to rebuild the router
  asynchronously (with eventual consistency between Nginx workers).
  [#4639](https://github.com/Kong/kong/pull/4639)
- :fireworks: **Database cache warmup**: Kong can now preload entities during
  its initialization. A new configuration property (`db_cache_warmup_entities`)
  was introduced, allowing users to specify which entities should be preloaded.
  DB cache warmup allows for ahead-of-time DNS resolution for Services with a
  hostname. This feature reduces first requests latency, improving the overall
  P99 latency tail.
  [#4565](https://github.com/Kong/kong/pull/4565)
- Improved PostgreSQL connection management: two new configuration properties
  have been added: `pg_max_concurrent_queries` sets the maximum number of
  concurrent queries to the database, and `pg_semaphore_timeout` allows for
  tuning the timeout when acquiring access to a database connection. The
  default behavior remains the same, with no concurrency limitation.
  [#4551](https://github.com/Kong/kong/pull/4551)

##### Admin API

- :fireworks: Add declarative configuration **hash checking** avoiding
  reloading if the configuration has not changed. The `/config` endpoint now
  accepts a `check_hash` query argument. Hash checking only happens if this
  argument's value is set to `1`.
  [#4609](https://github.com/Kong/kong/pull/4609)
- :fireworks: Add a **schema validation endpoint for entities**: a new
  endpoint `/schemas/:entity_name/validate` can be used to validate an instance
  of any entity type in Kong without creating the entity itself.
  [#4413](https://github.com/Kong/kong/pull/4413)
- :fireworks: Add **memory statistics** to the `/status` endpoint. The response
  now includes a `memory` field, which contains the `lua_shared_dicts` and
  `workers_lua_vms` fields with statistics on shared dictionaries and workers
  Lua VM memory usage.
  [#4592](https://github.com/Kong/kong/pull/4592)

##### PDK

- New function `kong.node.get_memory_stats()`. This function returns statistics
  on shared dictionaries and workers Lua VM memory usage, and powers the memory
  statistics newly exposed by the `/status` endpoint.
  [#4632](https://github.com/Kong/kong/pull/4632)

##### Plugins

- :fireworks: **Newly open-sourced plugin**: the HTTP [proxy-cache
  plugin](https://github.com/kong/kong-plugin-proxy-cache) (previously only
  available in Enterprise) is now bundled in Kong.
  [#4650](https://github.com/Kong/kong/pull/4650)
- :fireworks: **Newly open-sourced plugin capabilities**: The
  [request-transformer
  plugin](https://github.com/Kong/kong-plugin-request-transformer) now includes
  capabilities previously only available in Enterprise, among which templating
  and variables interpolation.
  [#4658](https://github.com/Kong/kong/pull/4658)
- Logging plugins: log request TLS version, cipher, and verification status.
  [#4581](https://github.com/Kong/kong/pull/4581)
  [#4626](https://github.com/Kong/kong/pull/4626)
- Plugin development: inheriting from `BasePlugin` is now optional. Avoiding
  the inheritance paradigm improves plugins' performance.
  [#4590](https://github.com/Kong/kong/pull/4590)

### Fixes

##### Core

- Active healthchecks: `http` checks are not performed for `tcp` and `tls`
  Services anymore; only `tcp` healthchecks are performed against such
  Services.
  [#4616](https://github.com/Kong/kong/pull/4616)
- Fix an issue where updates in migrations would not correctly populate default
  values.
  [#4635](https://github.com/Kong/kong/pull/4635)
- Improvements in the reentrancy of Cassandra migrations.
  [#4611](https://github.com/Kong/kong/pull/4611)
- Fix an issue causing the PostgreSQL strategy to not bootstrap the schema when
  using a PostgreSQL account with limited permissions.
  [#4506](https://github.com/Kong/kong/pull/4506)

##### CLI

- Fix `kong db_import` to support inserting entities without specifying a UUID
  for their primary key. Entities with a unique identifier (e.g. `name` for
  Services) can have their primary key omitted.
  [#4657](https://github.com/Kong/kong/pull/4657)
- The `kong migrations [up|finish] -f` commands does not run anymore if there
  are no previously executed migrations.
  [#4617](https://github.com/Kong/kong/pull/4617)

##### Plugins

- ldap-auth: ensure TLS connections are reused.
  [#4620](https://github.com/Kong/kong/pull/4620)
- oauth2: ensured access tokens preserve their `token_expiration` value when
  migrating from previous Kong versions.
  [#4572](https://github.com/Kong/kong/pull/4572)

[Back to TOC](#table-of-contents)

## [1.1.2]

> Released on: 2019/04/24

This is a patch release in the 1.0 series. Being a patch release, it strictly
contains bugfixes. The are no new features or breaking changes.

### Fixes

- core: address issue where field type "record" nested values reset on update
  [#4495](https://github.com/Kong/kong/pull/4495)
- core: correctly manage primary keys of type "foreign"
  [#4429](https://github.com/Kong/kong/pull/4429)
- core: declarative config is not parsed on db-mode anymore
  [#4487](https://github.com/Kong/kong/pull/4487)
  [#4509](https://github.com/Kong/kong/pull/4509)
- db-less: Fixed a problem in Kong balancer timing out.
  [#4534](https://github.com/Kong/kong/pull/4534)
- db-less: Accept declarative config directly in JSON requests.
  [#4527](https://github.com/Kong/kong/pull/4527)
- db-less: do not mis-detect mesh mode
  [#4498](https://github.com/Kong/kong/pull/4498)
- db-less: fix crash when field has same name as entity
  [#4478](https://github.com/Kong/kong/pull/4478)
- basic-auth: ignore password if nil on basic auth credential patch
  [#4470](https://github.com/Kong/kong/pull/4470)
- http-log: Simplify queueing mechanism. Fixed a bug where traces were lost
  in some cases.
  [#4510](https://github.com/Kong/kong/pull/4510)
- request-transformer: validate header values in plugin configuration.
  Thanks, [@rune-chan](https://github.com/rune-chan)!
  [#4512](https://github.com/Kong/kong/pull/4512).
- rate-limiting: added index on rate-limiting metrics.
  Thanks, [@mvanholsteijn](https://github.com/mvanholsteijn)!
  [#4486](https://github.com/Kong/kong/pull/4486)

[Back to TOC](#table-of-contents)

## [1.1.1]

> Released on: 2019/03/28

This release contains a fix for 0.14 Kong clusters using Cassandra to safely
migrate to Kong 1.1.

### Fixes

- Ensure the 0.14 -> 1.1 migration path for Cassandra does not corrupt the
  database schema.
  [#4450](https://github.com/Kong/kong/pull/4450)
- Allow the `kong config init` command to run without a pointing to a prefix
  directory.
  [#4451](https://github.com/Kong/kong/pull/4451)

[Back to TOC](#table-of-contents)

## [1.1.0]

> Released on: 2019/03/27

This release introduces new features such as **Declarative
Configuration**, **DB-less Mode**, **Bulk Database Import**, **Tags**, as well
as **Transparent Proxying**. It contains a large number of other features and
fixes, listed below. Also, the Plugin Development kit also saw a minor
updated, bumped to version 1.1.

This release includes database migrations. Please take a few minutes to read
the [1.1 Upgrade Path](https://github.com/Kong/kong/blob/master/UPGRADE.md)
for more details regarding changes and migrations before planning to upgrade
your Kong cluster.

:large_orange_diamond: **Post-release note (as of 2019/03/28):** an issue has
been found when migrating from a 0.14 Kong cluster to 1.1.0 when running on top
of Cassandra. Kong 1.1.1 has been released to address this issue. Kong clusters
running on top of PostgreSQL are not affected by this issue, and can migrate to
1.1.0 or 1.1.1 safely.

### Additions

##### Core

- :fireworks: Kong can now run **without a database**, using in-memory
  storage only. When running Kong in DB-less mode, entities are loaded via a
  **declarative configuration** file, specified either through Kong's
  configuration file, or uploaded via the Admin API.
  [#4315](https://github.com/Kong/kong/pull/4315)
- :fireworks: **Transparent proxying** - the `service` attribute on
  Routes is now optional; a Route without an assigned Service will
  proxy transparently
  [#4286](https://github.com/Kong/kong/pull/4286)
- Support for **tags** in entities
  [#4275](https://github.com/Kong/kong/pull/4275)
  - Every core entity now adds a `tags` field
- New `protocols` field in the Plugin entity, allowing plugin instances
  to be set for specific protocols only (`http`, `https`, `tcp` or `tls`).
  [#4248](https://github.com/Kong/kong/pull/4248)
  - It filters out plugins during execution according to their `protocols` field
  - It throws an error when trying to associate a Plugin to a Route
    which is not compatible, protocols-wise, or to a Service with no
    compatible routes.

##### Configuration

- New option in `kong.conf`: `database=off` to start Kong without
  a database
- New option in `kong.conf`: `declarative_config=kong.yml` to
  load a YAML file using Kong's new [declarative config
  format](https://discuss.konghq.com/t/rfc-kong-native-declarative-config-format/2719)
- New option in `kong.conf`: `pg_schema` to specify Postgres schema
  to be used
- The Stream subsystem now supports Nginx directive injections
  [#4148](https://github.com/Kong/kong/pull/4148)
  - `nginx_stream_*` (or `KONG_NGINX_STREAM_*` environment variables)
    for injecting entries to the `stream` block
  - `nginx_sproxy_*` (or `KONG_NGINX_SPROXY_*` environment variables)
    for injecting entries to the `server` block inside `stream`

##### CLI

- :fireworks: **Bulk database import** using the same declarative
  configuration format as the in-memory mode, using the new command:
  `kong config db_import kong.yml`. This command upserts all
  entities specified in the given `kong.yml` file in bulk
  [#4284](https://github.com/Kong/kong/pull/4284)
- New command: `kong config init` to generate a template `kong.yml`
  file to get you started
- New command: `kong config parse kong.yml` to verify the syntax of
  the `kong.yml` file before using it
- New option `--wait` in `kong quit` to ease graceful termination when using orchestration tools
  [#4201](https://github.com/Kong/kong/pull/4201)

##### Admin API

- New Admin API endpoint: `/config` to replace the configuration of
  Kong entities entirely, replacing it with the contents of a new
  declarative config file
  - When using the new `database=off` configuration option,
    the Admin API endpoints for entities (such as `/routes` and
    `/services`) are read-only, since the configuration can only
    be updated via `/config`
    [#4308](https://github.com/Kong/kong/pull/4308)
- Admin API endpoints now support searching by tag
  (for example, `/consumers?tags=example_tag`)
  - You can search by multiple tags:
     - `/services?tags=serv1,mobile` to search for services matching tags `serv1` and `mobile`
     - `/services?tags=serv1/serv2` to search for services matching tags `serv1` or `serv2`
- New Admin API endpoint `/tags/` for listing entities by tag: `/tags/example_tag`

##### PDK

- New PDK function: `kong.client.get_protocol` for obtaining the protocol
  in use during the current request
  [#4307](https://github.com/Kong/kong/pull/4307)
- New PDK function: `kong.nginx.get_subsystem`, so plugins can detect whether
  they are running on the HTTP or Stream subsystem
  [#4358](https://github.com/Kong/kong/pull/4358)

##### Plugins

- :fireworks: Support for ACL **authenticated groups**, so that authentication plugins
  that use a 3rd party (other than Kong) to store credentials can benefit
  from using a central ACL plugin to do authorization for them
  [#4013](https://github.com/Kong/kong/pull/4013)
- The Kubernetes Sidecar Injection plugin is now bundled into Kong for a smoother K8s experience
  [#4304](https://github.com/Kong/kong/pull/4304)
- aws-lambda: includes AWS China region.
  Thanks [@wubins](https://github.com/wubins) for the patch!
  [#4176](https://github.com/Kong/kong/pull/4176)

### Changes

##### Dependencies

- The required OpenResty version is still 1.13.6.2, but for a full feature set
  including stream routing and Service Mesh abilities with mutual TLS, Kong's
  [openresty-patches](https://github.com/kong/openresty-patches) must be
  applied (those patches are already bundled with our official distribution
  packages). The openresty-patches bundle was updated in Kong 1.1.0 to include
  the `stream_realip_module` as well.
  Kong in HTTP(S) Gateway scenarios does not require these patches.
  [#4163](https://github.com/Kong/kong/pull/4163)
- Service Mesh abilities require at least OpenSSL version 1.1.1. In our
  official distribution packages, OpenSSL has been bumped to 1.1.1b.
  [#4345](https://github.com/Kong/kong/pull/4345),
  [#4440](https://github.com/Kong/kong/pull/4440)

### Fixes

##### Core

- Resolve hostnames properly during initialization of Cassandra contact points
  [#4296](https://github.com/Kong/kong/pull/4296),
  [#4378](https://github.com/Kong/kong/pull/4378)
- Fix health checks for Targets that need two-level DNS resolution
  (e.g. SRV → A → IP) [#4386](https://github.com/Kong/kong/pull/4386)
- Fix serialization of map types in the Cassandra backend
  [#4383](https://github.com/Kong/kong/pull/4383)
- Fix target cleanup and cascade-delete for Targets
  [#4319](https://github.com/Kong/kong/pull/4319)
- Avoid crash when failing to obtain list of Upstreams
  [#4301](https://github.com/Kong/kong/pull/4301)
- Disallow invalid timeout value of 0ms for attributes in Services
  [#4430](https://github.com/Kong/kong/pull/4430)
- DAO fix for foreign fields used as primary keys
  [#4387](https://github.com/Kong/kong/pull/4387)

##### Admin API

- Proper support for `PUT /{entities}/{entity}/plugins/{plugin}`
  [#4288](https://github.com/Kong/kong/pull/4288)
- Fix Admin API inferencing of map types using form-encoded
  [#4368](https://github.com/Kong/kong/pull/4368)
- Accept UUID-like values in `/consumers?custom_id=`
  [#4435](https://github.com/Kong/kong/pull/4435)

##### Plugins

- basic-auth, ldap-auth, key-auth, jwt, hmac-auth: fixed
  status code for unauthorized requests: they now return HTTP 401
  instead of 403
  [#4238](https://github.com/Kong/kong/pull/4238)
- tcp-log: remove spurious trailing carriage return
  Thanks [@cvuillemez](https://github.com/cvuillemez) for the patch!
  [#4158](https://github.com/Kong/kong/pull/4158)
- jwt: fix `typ` handling for supporting JOSE (JSON Object
  Signature and Validation)
  Thanks [@cdimascio](https://github.com/cdimascio) for the patch!
  [#4256](https://github.com/Kong/kong/pull/4256)
- Fixes to the best-effort auto-converter for legacy plugin schemas
  [#4396](https://github.com/Kong/kong/pull/4396)

[Back to TOC](#table-of-contents)

## [1.0.3]

> Released on: 2019/01/31

This is a patch release addressing several regressions introduced some plugins,
and improving the robustness of our migrations and core components.

### Core

- Improve Cassandra schema consensus logic when running migrations.
  [#4233](https://github.com/Kong/kong/pull/4233)
- Ensure Routes that don't have a `regex_priority` (e.g. if it was removed as
  part of a `PATCH`) don't prevent the router from being built.
  [#4255](https://github.com/Kong/kong/pull/4255)
- Reduce rebuild time of the load balancer by retrieving larger sized pages of
  Target entities.
  [#4206](https://github.com/Kong/kong/pull/4206)
- Ensure schema definitions of Arrays and Sets with `default = {}` are
  JSON-encoded as `[]`.
  [#4257](https://github.com/Kong/kong/pull/4257)

##### Plugins

- request-transformer: fix a regression causing the upstream Host header to be
  unconditionally set to that of the client request (effectively, as if the
  Route had `preserve_host` enabled).
  [#4253](https://github.com/Kong/kong/pull/4253)
- cors: fix a regression that prevented regex origins from being matched.
  Regexes such as `(.*[.])?example\.org` can now be used to match all
  sub-domains, while regexes containing `:` will be evaluated against the
  scheme and port of an origin (i.e.
  `^https?://(.*[.])?example\.org(:8000)?$`).
  [#4261](https://github.com/Kong/kong/pull/4261)
- oauth2: fix a runtime error when using a global token against a plugin
  not configured as global (i.e. with `global_credentials = false`).
  [#4262](https://github.com/Kong/kong/pull/4262)

##### Admin API

- Improve performance of the `PUT` method in auth plugins endpoints (e.g.
  `/consumers/:consumers/basic-auth/:basicauth_credentials`) by preventing
  a unnecessary read-before-write.
  [#4206](https://github.com/Kong/kong/pull/4206)

[Back to TOC](#table-of-contents)

## [1.0.2]

> Released on: 2019/01/18

This is a hotfix release mainly addressing an issue when connecting to the
datastore over TLS (Cassandra and PostgreSQL).

### Fixes

##### Core

- Fix an issue that would prevent Kong from starting when connecting to
  its datastore over TLS. [#4214](https://github.com/Kong/kong/pull/4214)
  [#4218](https://github.com/Kong/kong/pull/4218)
- Ensure plugins added via `PUT` get enabled without requiring a restart.
  [#4220](https://github.com/Kong/kong/pull/4220)

##### Plugins

- zipkin
  - Fix a logging failure when DNS is not resolved.
    [kong-plugin-zipkin@a563f51](https://github.com/Kong/kong-plugin-zipkin/commit/a563f513f943ba0a30f3c69373d9092680a8f670)
  - Avoid sending redundant tags.
    [kong-plugin-zipkin/pull/28](https://github.com/Kong/kong-plugin-zipkin/pull/28)
  - Move `run_on` field to top level plugin schema instead of its config.
    [kong-plugin-zipkin/pull/38](https://github.com/Kong/kong-plugin-zipkin/pull/38)

[Back to TOC](#table-of-contents)

## [1.0.1]

> Released on: 2019/01/16

This is a patch release in the 1.0 series. Being a patch release, it strictly
contains performance improvements and bugfixes. The are no new features or
breaking changes.

:red_circle: **Post-release note (as of 2019/01/17)**: A regression has been
observed with this version, preventing Kong from starting when connecting to
its datastore over TLS. Installing this version is discouraged; consider
upgrading to [1.0.2](#102).

### Changes

##### Core

- :rocket: Assorted changes for warmup time improvements over Kong 1.0.0
  [#4138](https://github.com/kong/kong/issues/4138),
  [#4164](https://github.com/kong/kong/issues/4164),
  [#4178](https://github.com/kong/kong/pull/4178),
  [#4179](https://github.com/kong/kong/pull/4179),
  [#4182](https://github.com/kong/kong/pull/4182)

### Fixes

##### Configuration

- Ensure `lua_ssl_verify_depth` works even when `lua_ssl_trusted_certificate`
  is not set
  [#4165](https://github.com/kong/kong/pull/4165).
  Thanks [@rainest](https://github.com/rainest) for the patch.
- Ensure Kong starts when only a `stream` listener is enabled
  [#4195](https://github.com/kong/kong/pull/4195)
- Ensure Postgres works with non-`public` schemas
  [#4198](https://github.com/kong/kong/pull/4198)

##### Core

- Fix an artifact in upstream migrations where `created_at`
  timestamps would occasionally display fractional values
  [#4183](https://github.com/kong/kong/issues/4183),
  [#4204](https://github.com/kong/kong/pull/4204)
- Fixed issue with HTTP/2 support advertisement
  [#4203](https://github.com/kong/kong/pull/4203)

##### Admin API

- Fixed handling of invalid targets in `/upstreams` endpoints
  for health checks
  [#4132](https://github.com/kong/kong/issues/4132),
  [#4205](https://github.com/kong/kong/pull/4205)
- Fixed the `/plugins/schema/:name` endpoint, as it was failing in
  some cases (e.g. the `datadog` plugin) and producing incorrect
  results in others (e.g. `request-transformer`).
  [#4136](https://github.com/kong/kong/issues/4136),
  [#4137](https://github.com/kong/kong/issues/4137)
  [#4151](https://github.com/kong/kong/pull/4151),
  [#4162](https://github.com/kong/kong/pull/4151)

##### Plugins

- Fix PDK memory leaks in `kong.service.response` and `kong.ctx`
  [#4143](https://github.com/kong/kong/pull/4143),
  [#4172](https://github.com/kong/kong/pull/4172)

[Back to TOC](#table-of-contents)

## [1.0.0]

> Released on: 2018/12/18

This is a major release, introducing new features such as **Service Mesh** and
**Stream Routing** support, as well as a **New Migrations** framework. It also
includes version 1.0.0 of the **Plugin Development Kit**. It contains a large
number of other features and fixes, listed below. Also, all plugins included
with Kong 1.0 are updated to use version 1.0 of the PDK.

As usual, major version upgrades require database migrations and changes to the
Nginx configuration file (if you customized the default template). Please take
a few minutes to read the [1.0 Upgrade
Path](https://github.com/Kong/kong/blob/master/UPGRADE.md) for more details
regarding breaking changes and migrations before planning to upgrade your Kong
cluster.

Being a major version, all entities and concepts that were marked as deprecated
in Kong 0.x are now removed in Kong 1.0. The deprecated features are retained
in [Kong 0.15](#0150), the final entry in the Kong 0.x series, which is being
released simultaneously to Kong 1.0.

### Changes

Kong 1.0 includes all breaking changes from 0.15, as well as the removal
of deprecated concepts.

##### Dependencies

- The required OpenResty version is still 1.13.6.2, but for a full feature set
  including stream routing and Service Mesh abilities with mutual TLS, Kong's
  [openresty-patches](https://github.com/kong/openresty-patches) must be
  applied (those patches are already bundled with our official distribution
  packages). Kong in HTTP(S) Gateway scenarios does not require these patches.
- Service Mesh abilities require at least OpenSSL version 1.1.1. In our
  official distribution packages, OpenSSL has been bumped to 1.1.1.
  [#4005](https://github.com/Kong/kong/pull/4005)

##### Configuration

- :warning: The `custom_plugins` directive is removed (deprecated since 0.14.0,
  July 2018). Use `plugins` instead.
- Modifications must be applied to the Nginx configuration. You are not
  affected by this change if you do not use a custom Nginx template. See the
  [1.0 Upgrade Path](https://github.com/Kong/kong/blob/master/UPGRADE.md) for
  a diff of changes to apply.
- The default value for `cassandra_lb_policy` changed from `RoundRobin` to
  `RequestRoundRobin`. This helps reducing the amount of new connections being
  opened during a request when using the Cassandra strategy.
  [#4004](https://github.com/Kong/kong/pull/4004)

##### Core

- :warning: The **API** entity and related concepts such as the `/apis`
  endpoint, are removed (deprecated since 0.13.0, March 2018). Use **Routes**
  and **Services** instead.
- :warning: The **old DAO** implementation is removed, along with the
  **old schema** validation library (`apis` was the last entity using it).
  Use the new schema format instead in custom plugins.
  To ease the transition of plugins, the plugin loader in 1.0 includes
  a _best-effort_ schema auto-translator, which should be sufficient for many
  plugins.
- Timestamps now bear millisecond precision in their decimal part.
  [#3660](https://github.com/Kong/kong/pull/3660)
- The PDK function `kong.request.get_body` will now return `nil, err, mime`
  when the body is valid JSON but neither an object nor an array.
  [#4063](https://github.com/Kong/kong/pull/4063)

##### CLI

- :warning: The new migrations framework (detailed below) has a different usage
  (and subcommands) compared to its predecessor.
  [#3802](https://github.com/Kong/kong/pull/3802)

##### Admin API

- :warning: In the 0.14.x release, Upstreams, Targets, and Plugins were still
  implemented using the old DAO and Admin API. In 0.15.0 and 1.0.0, all core
  entities use the new `kong.db` DAO, and their endpoints have been upgraded to
  the new Admin API (see below for details).
  [#3689](https://github.com/Kong/kong/pull/3689)
  [#3739](https://github.com/Kong/kong/pull/3739)
  [#3778](https://github.com/Kong/kong/pull/3778)

A summary of the changes introduced in the new Admin API:

- Pagination has been included in all "multi-record" endpoints, and pagination
  control fields are different than in 0.14.x.
- Filtering now happens via URL path changes (`/consumers/x/plugins`) instead
  of querystring fields (`/plugins?consumer_id=x`).
- Array values can't be coerced from comma-separated strings anymore. They must
  now be "proper" JSON values on JSON requests, or use a new syntax on
  form-url-encoded or multipart requests.
- Error messages have been been reworked from the ground up to be more
  consistent, precise and informative.
- The `PUT` method has been reimplemented with idempotent behavior and has
  been added to some entities that didn't have it.

For more details about the new Admin API, please visit the official docs:
https://docs.konghq.com/

##### Plugins

- :warning: The `galileo` plugin has been removed (deprecated since 0.13.0).
  [#3960](https://github.com/Kong/kong/pull/3960)
- :warning: Some internal modules that were occasionally used by plugin authors
  before the introduction of the Plugin Development Kit (PDK) in 0.14.0 are now
  removed:
  - The `kong.tools.ip` module was removed. Use `kong.ip` from the PDK instead.
  - The `kong.tools.public` module was removed. Use the various equivalent
    features from the PDK instead.
  - The `kong.tools.responses` module was removed. Please use
    `kong.response.exit` from the PDK instead. You might want to use
    `kong.log.err` to log internal server errors as well.
  - The `kong.api.crud_helpers` module was removed (deprecated since the
    introduction of the new DAO in 0.13.0). Use `kong.api.endpoints` instead
    if you need to customize the auto-generated endpoints.
- All bundled plugins' schemas and custom entities have been updated to the new
  `kong.db` module, and their APIs have been updated to the new Admin API,
  which is described in the above section.
  [#3766](https://github.com/Kong/kong/pull/3766)
  [#3774](https://github.com/Kong/kong/pull/3774)
  [#3778](https://github.com/Kong/kong/pull/3778)
  [#3839](https://github.com/Kong/kong/pull/3839)
- :warning: All plugins migrations have been converted to the new migration
  framework. Custom plugins must use the new migration framework from 0.15
  onwards.

### Additions

##### :fireworks: Service Mesh and Stream Routes

Kong's Service Mesh support resulted in a number of additions to Kong's
configuration, Admin API, and plugins that deserve their own section in
this changelog.

- **Support for TCP & TLS Stream Routes** via the new `stream_listen` config
  option. [#4009](https://github.com/Kong/kong/pull/4009)
- A new `origins` config property allows overriding hosts from Kong.
  [#3679](https://github.com/Kong/kong/pull/3679)
- A `transparent` suffix added to stream listeners allows for setting up a
  dynamic Service Mesh with `iptables`.
  [#3884](https://github.com/Kong/kong/pull/3884)
- Kong instances can now create a shared internal Certificate Authority, which
  is used for Service Mesh TLS traffic.
  [#3906](https://github.com/Kong/kong/pull/3906)
  [#3861](https://github.com/Kong/kong/pull/3861)
- Plugins get a new `run_on` field to control how they behave in a Service Mesh
  environment.
  [#3930](https://github.com/Kong/kong/pull/3930)
  [#4066](https://github.com/Kong/kong/pull/4066)
- There is a new phase called `preread`. This is where stream traffic routing
  is done.

##### Configuration

- A new `dns_valid_ttl` property can be set to forcefully override the TTL
  value of all resolved DNS records.
  [#3730](https://github.com/Kong/kong/pull/3730)
- A new `pg_timeout` property can be set to configure the timeout of PostgreSQL
  connections. [#3808](https://github.com/Kong/kong/pull/3808)
- `upstream_keepalive` can now be disabled when set to 0.
  Thanks [@pryorda](https://github.com/pryorda) for the patch.
  [#3716](https://github.com/Kong/kong/pull/3716)
- The new `transparent` suffix also applies to the `proxy_listen` directive.

##### CLI

- :fireworks: **New migrations framework**. This new implementation supports
  no-downtime, Blue/Green migrations paths that will help sustain Kong 1.0's
  stability. It brings a considerable number of other improvements, such as new
  commands, better support for automation, improved CLI logging, and many
  more. Additionally, this new framework alleviates the old limitation around
  multiple nodes running concurrent migrations. See the related PR for a
  complete list of improvements.
  [#3802](https://github.com/Kong/kong/pull/3802)

##### Core

- :fireworks: **Support for TLS 1.3**. The support for OpenSSL 1.1.1 (bumped in our
  official distribution packages) not only enabled Service Mesh features, but
  also unlocks support for the latest version of the TLS protocol.
- :fireworks: **Support for HTTPS in active healthchecks**.
  [#3815](https://github.com/Kong/kong/pull/3815)
- :fireworks: Improved router rebuilds resiliency by reducing database accesses
  in high concurrency scenarios.
  [#3782](https://github.com/Kong/kong/pull/3782)
- :fireworks: Significant performance improvements in the core's plugins
  runloop. [#3794](https://github.com/Kong/kong/pull/3794)
- PDK improvements:
  - New `kong.node` module. [#3826](https://github.com/Kong/kong/pull/3826)
  - New functions `kong.response.get_path_with_query()` and
    `kong.request.get_start_time()`.
    [#3842](https://github.com/Kong/kong/pull/3842)
  - Getters and setters for Service, Route, Consumer, and Credential.
    [#3916](https://github.com/Kong/kong/pull/3916)
  - `kong.response.get_source()` returns `error` on nginx-produced errors.
    [#4006](https://github.com/Kong/kong/pull/4006)
  - `kong.response.exit()` can be used in the `header_filter` phase, but only
    without a body. [#4039](https://github.com/Kong/kong/pull/4039)
- Schema improvements:
  - New field validators: `distinct`, `ne`, `is_regex`, `contains`, `gt`.
  - Adding a new field which has a default value to a schema no longer requires
    a migration.
    [#3756](https://github.com/Kong/kong/pull/3756)

##### Admin API

- :fireworks: **Routes now have a `name` field (like Services)**.
  [#3764](https://github.com/Kong/kong/pull/3764)
- Multipart parsing support. [#3776](https://github.com/Kong/kong/pull/3776)
- Admin API errors expose the name of the current strategy.
  [#3612](https://github.com/Kong/kong/pull/3612)

##### Plugins

- :fireworks: aws-lambda: **Support for Lambda Proxy Integration** with the new
  `is_proxy_integration` property.
  Thanks [@aloisbarreras](https://github.com/aloisbarreras) for the patch!
  [#3427](https://github.com/Kong/kong/pull/3427/).
- http-log: Support for buffering logging messages in a configurable logging
  queue. [#3604](https://github.com/Kong/kong/pull/3604)
- Most plugins' logic has been rewritten with the PDK instead of using internal
  Kong functions or ngx_lua APIs.

### Fixes

##### Core

- Fix an issue which would insert an extra `/` in the upstream URL when the
  request path was longer than the configured Route's `path` attribute.
  [#3780](https://github.com/kong/kong/pull/3780)
- Ensure better backwards-compatibility between the new DAO and existing core
  runloop code regarding null values.
  [#3772](https://github.com/Kong/kong/pull/3772)
  [#3710](https://github.com/Kong/kong/pull/3710)
- Ensure support for Datastax Enterprise 6.x. Thanks
  [@gchristidis](https://github.com/gchristidis) for the patch!
  [#3873](https://github.com/Kong/kong/pull/3873)
- Various issues with the PostgreSQL DAO strategy were addressed.
- Various issues related to the new schema library bundled with the new DAO
  were addressed.
- PDK improvements:
    - `kong.request.get_path()` and other functions now properly handle cases
      when `$request_uri` is nil.
      [#3842](https://github.com/Kong/kong/pull/3842)

##### Admin API

- Ensure the `/certificates` endpoints properly returns all SNIs configured on
  a given certificate. [#3722](https://github.com/Kong/kong/pull/3722)
- Ensure the `upstreams/:upstream/targets/...` endpoints returns an empty JSON
  array (`[]`) instead of an empty object (`{}`) when no targets exist.
  [#4058](https://github.com/Kong/kong/pull/4058)
- Improved inferring of arguments with `application/x-www-form-urlencoded`.
  [#3770](https://github.com/Kong/kong/pull/3770)
- Fix the handling of defaults values in some cases when using `PATCH`.
  [#3910](https://github.com/Kong/kong/pull/3910)

##### Plugins

- cors:
  - Ensure `Vary: Origin` is set when `config.credentials` is enabled.
    Thanks [@marckhouzam](https://github.com/marckhouzam) for the patch!
    [#3765](https://github.com/Kong/kong/pull/3765)
  - Return HTTP 200 instead of 204 for preflight requests. Thanks
    [@aslafy-z](https://github.com/aslafy-z) for the patch!
    [#4029](https://github.com/Kong/kong/pull/4029)
  - Ensure request origins specified as flat strings are safely validated.
    [#3872](https://github.com/Kong/kong/pull/3872)
- acl: Minor performance improvements by ensuring proper caching of computed
  values.
  [#4040](https://github.com/Kong/kong/pull/4040)
- correlation-id: Prevent an error to be thrown when the access phase was
  skipped, such as on nginx-produced errors.
  [#4006](https://github.com/Kong/kong/issues/4006)
- aws-lambda: When the client uses HTTP/2, strip response headers that are
  disallowed by the protocols.
  [#4032](https://github.com/Kong/kong/pull/4032)
- rate-limiting & response-ratelimiting: Improve efficiency by avoiding
  unnecessary Redis `SELECT` operations.
  [#3973](https://github.com/Kong/kong/pull/3973)

[Back to TOC](#table-of-contents)

## [0.15.0]

> Released on: 2018/12/18

This is the last release in the 0.x series, giving users one last chance to
upgrade while still using some of the options and concepts that were marked as
deprecated in Kong 0.x and were removed in Kong 1.0.

For a list of additions and fixes in Kong 0.15, see the [1.0.0](#100)
changelog. This release includes all new features included in 1.0 (Service
Mesh, Stream Routes and New Migrations), but unlike Kong 1.0, it retains a lot
of the deprecated functionality, like the **API** entity, around. Still, Kong
0.15 does have a number of breaking changes related to functionality that has
changed since version 0.14 (see below).

If you are starting with Kong, we recommend you to use 1.0.0 instead of this
release.

If you are already using Kong 0.14, our recommendation is to plan to move to
1.0 -- see the [1.0 Upgrade
Path](https://github.com/kong/kong/blob/master/UPGRADE.md) document for
details. Upgrading to 0.15.0 is only recommended if you can't do away with the
deprecated features but you need some fixes or new features right now.

### Changes

##### Dependencies

- The required OpenResty version is still 1.13.6.2, but for a full feature set
  including stream routing and Service Mesh abilities with mutual TLS, Kong's
  [openresty-patches](https://github.com/kong/openresty-patches) must be
  applied (those patches are already bundled with our official distribution
  packages). Kong in HTTP(S) Gateway scenarios does not require these patches.
- Service Mesh abilities require at least OpenSSL version 1.1.1. In our
  official distribution packages, OpenSSL has been bumped to 1.1.1.
  [#4005](https://github.com/Kong/kong/pull/4005)

##### Configuration

- The default value for `cassandra_lb_policy` changed from `RoundRobin` to
  `RequestRoundRobin`. This helps reducing the amount of new connections being
  opened during a request when using the Cassandra strategy.
  [#4004](https://github.com/Kong/kong/pull/4004)

##### Core

- Timestamps now bear millisecond precision in their decimal part.
  [#3660](https://github.com/Kong/kong/pull/3660)
- The PDK function `kong.request.get_body` will now return `nil, err, mime`
  when the body is valid JSON but neither an object nor an array.
  [#4063](https://github.com/Kong/kong/pull/4063)

##### CLI

- :warning: The new migrations framework (detailed in the [1.0.0
  changelog](#100)) has a different usage (and subcommands) compared to its
  predecessor.
  [#3802](https://github.com/Kong/kong/pull/3802)

##### Admin API

- :warning: In the 0.14.x release, Upstreams, Targets, and Plugins were still
  implemented using the old DAO and Admin API. In 0.15.0 and 1.0.0, all core
  entities use the new `kong.db` DAO, and their endpoints have been upgraded to
  the new Admin API (see below for details).
  [#3689](https://github.com/Kong/kong/pull/3689)
  [#3739](https://github.com/Kong/kong/pull/3739)
  [#3778](https://github.com/Kong/kong/pull/3778)

A summary of the changes introduced in the new Admin API:

- Pagination has been included in all "multi-record" endpoints, and pagination
  control fields are different than in 0.14.x.
- Filtering now happens via URL path changes (`/consumers/x/plugins`) instead
  of querystring fields (`/plugins?consumer_id=x`).
- Array values can't be coherced from comma-separated strings. They must be
  "proper" JSON values on JSON requests, or use a new syntax on
  form-url-encoded or multipart requests.
- Error messages have been been reworked from the ground up to be more
  consistent, precise and informative.
- The `PUT` method has been reimplemented with idempotent behavior and has
  been added to some entities that didn't have it.

For more details about the new Admin API, please visit the official docs:
https://docs.konghq.com/

##### Plugins

- All bundled plugins' schemas and custom entities have been updated to the new
  `kong.db` module, and their APIs have been updated to the new Admin API,
  which is described in the above section.
  [#3766](https://github.com/Kong/kong/pull/3766)
  [#3774](https://github.com/Kong/kong/pull/3774)
  [#3778](https://github.com/Kong/kong/pull/3778)
  [#3839](https://github.com/Kong/kong/pull/3839)
- :warning: All plugins migrations have been converted to the new migration
  framework. Custom plugins must use the new migration framework from 0.15
  onwards.

### Additions

Kong 0.15.0 contains the same additions as 1.0.0. See the [1.0.0
changelog](#100) for a complete list.

### Fixes

Kong 0.15.0 contains the same fixes as 1.0.0. See the [1.0.0 changelog](#100)
for a complete list.

[Back to TOC](#table-of-contents)

## [0.14.1]

> Released on: 2018/08/21

### Additions

##### Plugins

- jwt: Support for tokens signed with HS384 and HS512.
  Thanks [@kepkin](https://github.com/kepkin) for the patch.
  [#3589](https://github.com/Kong/kong/pull/3589)
- acl: Add a new `hide_groups_header` configuration option. If enabled, this
  option prevents the plugin from injecting the `X-Consumer-Groups` header
  into the upstream request.
  Thanks [@jeremyjpj0916](https://github.com/jeremyjpj0916) for the patch!
  [#3703](https://github.com/Kong/kong/pull/3703)

### Fixes

##### Core

- Prevent some plugins from breaking in subtle ways when manipulating some
  entities and their attributes. An example of such breaking behavior could be
  observed when Kong was wrongly injecting `X-Consumer-Username: userdata:
  NULL` in upstream requests headers, instead of not injecting this header at
  all.
  [#3714](https://github.com/Kong/kong/pull/3714)
- Fix an issue which, in some cases, prevented the use of Kong with Cassandra
  in environments where DNS load-balancing is in effect for contact points
  provided as hostnames (e.g. Kubernetes with `cassandra_contact_points =
  cassandra`).
  [#3693](https://github.com/Kong/kong/pull/3693)
- Fix an issue which prevented the use of UNIX domain sockets in some logging
  plugins, and custom plugins making use of such sockets.
  Thanks [@rucciva](https://github.com/rucciva) for the patch.
  [#3633](https://github.com/Kong/kong/pull/3633)
- Avoid logging false-negative error messages related to worker events.
  [#3692](https://github.com/Kong/kong/pull/3692)

##### CLI

- Database connectivity errors are properly prefixed with the database name
  again (e.g. `[postgres]`).
  [#3648](https://github.com/Kong/kong/pull/3648)

##### Plugins

- zipkin
  - Allow usage of the plugin with the deprecated "API" entity, and introduce
    a new `kong.api` tag.
    [kong-plugin-zipkin/commit/4a645e9](https://github.com/Kong/kong-plugin-zipkin/commit/4a645e940e560f2e50567e0360b5df3b38f74853)
  - Properly report the `kong.credential` tag.
    [kong-plugin-zipkin/commit/c627c36](https://github.com/Kong/kong-plugin-zipkin/commit/c627c36402c9a14cc48011baa773f4ee08efafcf)
  - Ensure the plugin does not throw errors when no Route was matched.
    [kong-plugin-zipkin#19](https://github.com/Kong/kong-plugin-zipkin/issues/19)
- basic-auth: Passwords with whitespaces are not trimmed anymore.
  Thanks [@aloisbarreras](https://github.com/aloisbarreras) for the patch.
  [#3650](https://github.com/Kong/kong/pull/3650)
- hmac-auth: Ensure backward compatibility for clients generating signatures
  without the request's querystring, as is the case for Kong versions prior to
  0.14.0, which broke this behavior. Users of this plugin on previous versions
  of Kong can now safely upgrade to the 0.14 family.
  Thanks [@mlehner616](https://github.com/mlehner616) for the patch!
  [#3699](https://github.com/Kong/kong/pull/3699)
- ldap-auth
    - Set the WWW-Authenticate header authentication scheme accordingly with
      the `conf.header_type` property, which allows browsers to show the
      authentication popup automatically. Thanks
      [@francois-maillard](https://github.com/francois-maillard) for the patch.
      [#3656](https://github.com/Kong/kong/pull/3656)
    - Invalid authentication attempts do not block subsequent valid attempts
      anymore.
      [#3677](https://github.com/Kong/kong/pull/3677)

[Back to TOC](#table-of-contents)

## [0.14.0] - 2018/07/05

This release introduces the first version of the **Plugin Development Kit**: a
Lua SDK, comprised of a set of functions to ease the development of
custom plugins.

Additionally, it contains several major improvements consolidating Kong's
feature set and flexibility, such as the support for `PUT` endpoints on the
Admin API for idempotent workflows, the execution of plugins during
Nginx-produced errors, and the injection of **Nginx directives** without having
to rely on the custom Nginx configuration pattern!

Finally, new bundled plugins allow Kong to better integrate with **Cloud
Native** environments, such as Zipkin and Prometheus.

As usual, major version upgrades require database migrations and changes to the
Nginx configuration file (if you customized the default template). Please take
a few minutes to read the [0.14 Upgrade
Path](https://github.com/Kong/kong/blob/master/UPGRADE.md#upgrade-to-014x) for
more details regarding breaking changes and migrations before planning to
upgrade your Kong cluster.

### Breaking Changes

##### Dependencies

- :warning: The required OpenResty version has been bumped to 1.13.6.2. If you
  are installing Kong from one of our distribution packages, you are not
  affected by this change.
  [#3498](https://github.com/Kong/kong/pull/3498)
- :warning: Support for PostgreSQL 9.4 (deprecated in 0.12.0) is now dropped.
  [#3490](https://github.com/Kong/kong/pull/3490)
- :warning: Support for Cassandra 2.1 (deprecated in 0.12.0) is now dropped.
  [#3490](https://github.com/Kong/kong/pull/3490)

##### Configuration

- :warning: The `server_tokens` and `latency_tokens` configuration properties
  have been removed. Instead, a new `headers` configuration properties replaces
  them and allows for more granular settings of injected headers (e.g.
  `Server`, `Via`, `X-Kong-*-Latency`, etc...).
  [#3300](https://github.com/Kong/kong/pull/3300)
- :warning: New required `lua_shared_dict` entries must be added to the Nginx
  configuration. You are not affected by this change if you do not use a custom
  Nginx template.
  [#3557](https://github.com/Kong/kong/pull/3557)
- :warning: Other important modifications must be applied to the Nginx
  configuration. You are not affected by this change if you do not use a custom
  Nginx template.
  [#3533](https://github.com/Kong/kong/pull/3533)

##### Plugins

- :warning: The Runscope plugin has been dropped, based on the EoL announcement
  made by Runscope about their Traffic Inspector product.
  [#3495](https://github.com/Kong/kong/pull/3495)

##### Admin API

- :warning: The SSL Certificates and SNI entities have moved to the new DAO
  implementation. As such, the `/certificates` and `/snis` endpoints have
  received notable usability improvements, but suffer from a few breaking
  changes.
  [#3386](https://github.com/Kong/kong/pull/3386)
- :warning: The Consumers entity has moved to the new DAO implementation. As
  such, the `/consumers` endpoint has received notable usability improvements,
  but suffers from a few breaking changes.
  [#3437](https://github.com/Kong/kong/pull/3437)

### Changes

##### Configuration

- The default value of `db_cache_ttl` is now `0` (disabled). Now that our level
  of confidence around the new caching mechanism introduced in 0.11.0 is high
  enough, we consider `0` (no TTL) to be an appropriate default for production
  environments, as it offers a smoother cache consumption behavior and reduces
  database pressure.
  [#3492](https://github.com/Kong/kong/pull/3492)

##### Core

- :fireworks: Serve stale data from the database cache when the datastore
  cannot be reached. Such stale items are "resurrected" for `db_resurrect_ttl`
  seconds (see configuration section).
  [#3579](https://github.com/Kong/kong/pull/3579)
- Reduce LRU churning in the database cache against some workloads.
  [#3550](https://github.com/Kong/kong/pull/3550)

### Additions

##### Configuration

- :fireworks: **Support for injecting Nginx directives via configuration
  properties** (in the `kong.conf` file or via environment variables)! This new
  way of customizing the Nginx configuration should render obsolete the old way
  of maintaining a custom Nginx template in most cases!
  [#3530](https://github.com/Kong/kong/pull/3530)
- :fireworks: **Support for selectively disabling bundled plugins**. A new
  `plugins` configuration property is introduced, and is used to specify which
  plugins should be loaded by the node. Custom plugins should now be specified
  in this new property, and the `custom_plugins` property is **deprecated**.
  If desired, Kong administrators can specify a minimal set of plugins to load
  (instead of the default, bundled plugins), and **improve P99 latency**
  thanks to the resulting decrease in database traffic.
  [#3387](https://github.com/Kong/kong/pull/3387)
- The new `headers` configuration property allows for specifying the injection
  of a new header: `X-Kong-Upstream-Status`. When enabled, Kong will inject
  this header containing the HTTP status code of the upstream response in the
  client response. This is particularly useful for clients to distinguish
  upstream statuses upon rewriting of the response by Kong.
  [#3263](https://github.com/Kong/kong/pull/3263)
- A new `db_resurrect_ttl` configuration property can be set to customize
  the amount of time stale data can be resurrected for when it cannot be
  refreshed. Defaults to 30 seconds.
  [#3579](https://github.com/Kong/kong/pull/3579)
- Two new Cassandra load balancing policies are available: `RequestRoundRobin`
  and `RequestDCAwareRoundRobin`. Both policies guarantee that the same peer
  will be reused across several queries during the lifetime of a request, thus
  guaranteeing no new connection will be opened against a peer during this
  request.
  [#3545](https://github.com/Kong/kong/pull/3545)

##### Core

- :fireworks: **Execute plugins on Nginx-produced errors.** Now, when Nginx
  produces a 4xx error (upon invalid requests) or 5xx (upon failure from the
  load balancer to connect to a Service), Kong will execute the response phases
  of its plugins (`header_filter`, `body_filter`, `log`). As such, Kong logging
  plugins are not blind to such Nginx-produced errors anymore, and will start
  properly reporting them. Plugins should be built defensively against cases
  where their `rewrite` or `access` phases were not executed.
  [#3533](https://github.com/Kong/kong/pull/3533)
- :fireworks: **Support for cookie-based load balancing!**
  [#3472](https://github.com/Kong/kong/pull/3472)

##### Plugins

- :fireworks: **Introduction of the Plugin Development Kit!** A set of Lua
  functions and variables that will greatly ease and speed up the task of
  developing custom plugins.
  The Plugin Development Kit (PDK) allows the retrieval and manipulation of the
  request and response objects, as well as interacting with various core
  components (e.g. logging, load balancing, DAO, etc...) without having to rely
  on OpenResty functions, and with the guarantee of their forward-compatibility
  with future versions of Kong.
  [#3556](https://github.com/Kong/kong/pull/3556)
- :fireworks: **New bundled plugin: Zipkin**! This plugin allows Kong to sample
  traces and report them to a running Zipkin instance.
  (See: https://github.com/Kong/kong-plugin-zipkin)
  [#3434](https://github.com/Kong/kong/pull/3434)
- :fireworks: **New bundled plugin: Prometheus**! This plugin allows Kong to
  expose metrics in the Prometheus Exposition format. Available metrics include
  HTTP status codes, latencies histogram, bandwidth, and more...
  (See: https://github.com/Kong/kong-plugin-prometheus)
  [#3547](https://github.com/Kong/kong/pull/3547)
- :fireworks: **New bundled plugin: Azure Functions**! This plugin can be used
  to invoke [Microsoft Azure
  Functions](https://azure.microsoft.com/en-us/services/functions/), similarly
  to the already existing AWS Lambda and OpenWhisk plugins.
  (See: https://github.com/Kong/kong-plugin-azure-functions)
  [#3428](https://github.com/Kong/kong/pull/3428)
- :fireworks: **New bundled plugin: Serverless Functions**! Dynamically run Lua
  without having to write a full-fledged plugin. Lua code snippets can be
  uploaded via the Admin API and be executed during Kong's `access` phase.
  (See: https://github.com/Kong/kong-plugin-serverless-functions)
  [#3551](https://github.com/Kong/kong/pull/3551)
- jwt: Support for limiting the allowed expiration period of JWT tokens. A new
  `config.maximum_expiration` property can be set to indicate the maximum
  number of seconds the `exp` claim may be ahead in the future.
  Thanks [@mvanholsteijn](https://github.com/mvanholsteijn) for the patch!
  [#3331](https://github.com/Kong/kong/pull/3331)
- aws-lambda: Add `us-gov-west-1` to the list of allowed regions.
  [#3529](https://github.com/Kong/kong/pull/3529)

##### Admin API

- :fireworks: Support for `PUT` in new endpoints (e.g. `/services/{id or
  name}`, `/routes/{id}`, `/consumers/{id or username}`), allowing the
  development of idempotent configuration workflows when scripting the Admin
  API.
  [#3416](https://github.com/Kong/kong/pull/3416)
- Support for `PATCH` and `DELETE` on the `/services/{name}`,
  `/consumers/{username}`, and `/snis/{name}` endpoints.
  [#3416](https://github.com/Kong/kong/pull/3416)

### Fixes

##### Configuration

- Properly support IPv6 addresses in `proxy_listen` and `admin_listen`
  configuration properties.
  [#3508](https://github.com/Kong/kong/pull/3508)

##### Core

- IPv6 nameservers with a scope are now ignored by the DNS resolver.
  [#3478](https://github.com/Kong/kong/pull/3478)
- SRV records without a port number now returns the default port instead of
  `0`.
  [#3478](https://github.com/Kong/kong/pull/3478)
- Ensure DNS-based round robin load balancing starts at a randomized position
  to prevent all Nginx workers from starting with the same peer.
  [#3478](https://github.com/Kong/kong/pull/3478)
- Properly report timeouts in passive health checks. Previously, connection
  timeouts were counted as `tcp_failures`, and upstream timeouts were ignored.
  Health check users should ensure that their `timeout` settings reflect their
  intended behavior.
  [#3539](https://github.com/Kong/kong/pull/3539)
- Ensure active health check probe requests send the `Host` header.
  [#3496](https://github.com/Kong/kong/pull/3496)
- Overall, more reliable health checks healthiness counters behavior.
  [#3496](https://github.com/Kong/kong/pull/3496)
- Do not set `Content-Type` headers on HTTP 204 No Content responses.
  [#3351](https://github.com/Kong/kong/pull/3351)
- Ensure the PostgreSQL connector of the new DAO (used by Services, Routes,
  Consumers, and SSL certs/SNIs) is now fully re-entrant and properly behaves
  in busy workloads (e.g. scripting requests to the Admin API).
  [#3423](https://github.com/Kong/kong/pull/3423)
- Properly route HTTP/1.0 requests without a Host header when using the old
  deprecated "API" entity.
  [#3438](https://github.com/Kong/kong/pull/3438)
- Ensure that all Kong-produced errors respect the `headers` configuration
  setting (previously `server_tokens`) and do not include the `Server` header
  if not configured.
  [#3511](https://github.com/Kong/kong/pull/3511)
- Harden an existing Cassandra migration.
  [#3532](https://github.com/Kong/kong/pull/3532)
- Prevent the load balancer from needlessly rebuilding its state when creating
  Targets.
  [#3477](https://github.com/Kong/kong/pull/3477)
- Prevent some harmless error logs to be printed during startup when
  initialization takes more than a few seconds.
  [#3443](https://github.com/Kong/kong/pull/3443)

##### Plugins

- hmac: Ensure that empty request bodies do not pass validation if there is no
  digest header.
  Thanks [@mvanholsteijn](https://github.com/mvanholsteijn) for the patch!
  [#3347](https://github.com/Kong/kong/pull/3347)
- response-transformer: Prevent the plugin from throwing an error when its
  `access` handler did not get a chance to run (e.g. on short-circuited,
  unauthorized requests).
  [#3524](https://github.com/Kong/kong/pull/3524)
- aws-lambda: Ensure logging plugins subsequently run when this plugin
  terminates.
  [#3512](https://github.com/Kong/kong/pull/3512)
- request-termination: Ensure logging plugins subsequently run when this plugin
  terminates.
  [#3513](https://github.com/Kong/kong/pull/3513)

##### Admin API

- Requests to `/healthy` and `/unhealthy` endpoints for upstream health checks
  now properly propagate the new state to other nodes of a Kong cluster.
  [#3464](https://github.com/Kong/kong/pull/3464)
- Do not produce an HTTP 500 error when POST-ing to `/services` with an empty
  `url` argument.
  [#3452](https://github.com/Kong/kong/pull/3452)
- Ensure foreign keys are required when creating child entities (e.g.
  `service.id` when creating a Route). Previously some rows could have an empty
  `service_id` field.
  [#3548](https://github.com/Kong/kong/pull/3548)
- Better type inference in new endpoints (e.g. `/services`, `/routes`,
  `/consumers`) when using `application/x-www-form-urlencoded` MIME type.
  [#3416](https://github.com/Kong/kong/pull/3416)

[Back to TOC](#table-of-contents)

## [0.13.1] - 2018/04/23

This release contains numerous bug fixes and a few convenience features.
Notably, a best-effort/backwards-compatible approach is followed to resolve
`no memory` errors caused by the fragmentation of shared memory between the
core and plugins.

### Added

##### Core

- Cache misses are now stored in a separate shared memory zone from hits if
  such a zone is defined. This reduces cache turnover and can increase the
  cache hit ratio quite considerably.
  Users with a custom Nginx template are advised to define such a zone to
  benefit from this behavior:
  `lua_shared_dict kong_db_cache_miss 12m;`.
- We now ensure that the Cassandra or PostgreSQL instance Kong is connecting
  to falls within the supported version range. Deprecated versions result in
  warning logs. As a reminder, Kong 0.13.x supports Cassandra 2.2+,
  and PostgreSQL 9.5+. Cassandra 2.1 and PostgreSQL 9.4 are supported, but
  deprecated.
  [#3310](https://github.com/Kong/kong/pull/3310)
- HTTP 494 errors thrown by Nginx are now caught by Kong and produce a native,
  Kong-friendly response.
  Thanks [@ti-mo](https://github.com/ti-mo) for the contribution!
  [#3112](https://github.com/Kong/kong/pull/3112)

##### CLI

- Report errors when compiling custom Nginx templates.
  [#3294](https://github.com/Kong/kong/pull/3294)

##### Admin API

- Friendlier behavior of Routes schema validation: PATCH requests can be made
  without specifying all three of `methods`, `hosts`, or `paths` if at least
  one of the three is specified in the body.
  [#3364](https://github.com/Kong/kong/pull/3364)

##### Plugins

- jwt: Support for identity providers using JWKS by ensuring the
  `config.key_claim_name` values is looked for in the token header.
  Thanks [@brycehemme](https://github.com/brycehemme) for the contribution!
  [#3313](https://github.com/Kong/kong/pull/3313)
- basic-auth: Allow specifying empty passwords.
  Thanks [@zhouzhuojie](https://github.com/zhouzhuojie) and
  [@perryao](https://github.com/perryao) for the contributions!
  [#3243](https://github.com/Kong/kong/pull/3243)

### Fixed

##### Core

- Numerous users have reported `no memory` errors which were caused by
  circumstantial memory fragmentation. Such errors, while still possible if
  plugin authors are not careful, should now mostly be addressed.
  [#3311](https://github.com/Kong/kong/pull/3311)

  **If you are using a custom Nginx template, be sure to define the following
  shared memory zones to benefit from these fixes**:

  ```
  lua_shared_dict kong_db_cache_miss 12m;
  lua_shared_dict kong_rate_limiting_counters 12m;
  ```

##### CLI

- Redirect Nginx's stdout and stderr output to `kong start` when
  `nginx_daemon` is enabled (such as when using the Kong Docker image). This
  also prevents growing log files when Nginx redirects logs to `/dev/stdout`
  and `/dev/stderr` but `nginx_daemon` is disabled.
  [#3297](https://github.com/Kong/kong/pull/3297)

##### Admin API

- Set a Service's `port` to `443` when the `url` convenience parameter uses
  the `https://` scheme.
  [#3358](https://github.com/Kong/kong/pull/3358)
- Ensure PATCH requests do not return an error when un-setting foreign key
  fields with JSON `null`.
  [#3355](https://github.com/Kong/kong/pull/3355)
- Ensure the `/plugin/schema/:name` endpoint does not corrupt plugins' schemas.
  [#3348](https://github.com/Kong/kong/pull/3348)
- Properly URL-decode path segments of plugins endpoints accepting spaces
  (e.g. `/consumers/<consumer>/basic-auth/John%20Doe/`).
  [#3250](https://github.com/Kong/kong/pull/3250)
- Properly serialize boolean filtering values when using Cassandra.
  [#3362](https://github.com/Kong/kong/pull/3362)

##### Plugins

- rate-limiting/response-rate-limiting:
  - If defined in the Nginx configuration, will use a dedicated
    `lua_shared_dict` instead of using the `kong_cache` shared memory zone.
    This prevents memory fragmentation issues resulting in `no memory` errors
    observed by numerous users. Users with a custom Nginx template are advised
    to define such a zone to benefit from this fix:
    `lua_shared_dict kong_rate_limiting_counters 12m;`.
    [#3311](https://github.com/Kong/kong/pull/3311)
  - When using the Redis strategy, ensure the correct Redis database is
    selected. This issue could occur when several request and response
    rate-limiting were configured using different Redis databases.
    Thanks [@mengskysama](https://github.com/mengskysama) for the patch!
    [#3293](https://github.com/Kong/kong/pull/3293)
- key-auth: Respect request MIME type when re-encoding the request body
  if both `config.key_in_body` and `config.hide_credentials` are enabled.
  Thanks [@p0pr0ck5](https://github.com/p0pr0ck5) for the patch!
  [#3213](https://github.com/Kong/kong/pull/3213)
- oauth2: Return HTTP 400 on invalid `scope` type.
  Thanks [@Gman98ish](https://github.com/Gman98ish) for the patch!
  [#3206](https://github.com/Kong/kong/pull/3206)
- ldap-auth: Ensure the plugin does not throw errors when configured as a
  global plugin.
  [#3354](https://github.com/Kong/kong/pull/3354)
- hmac-auth: Verify signature against non-normalized (`$request_uri`) request
  line (instead of `$uri`).
  [#3339](https://github.com/Kong/kong/pull/3339)
- aws-lambda: Fix a typo in upstream headers sent to the function. We now
  properly send the `X-Amz-Log-Type` header.
  [#3398](https://github.com/Kong/kong/pull/3398)

[Back to TOC](#table-of-contents)

## [0.13.0] - 2018/03/22

This release introduces two new core entities that will improve the way you
configure Kong: **Routes** & **Services**. Those entities replace the "API"
entity and simplify the setup of non-naive use-cases by providing better
separation of concerns and allowing for plugins to be applied to specific
**endpoints**.

As usual, major version upgrades require database migrations and changes to
the Nginx configuration file (if you customized the default template).
Please take a few minutes to read the [0.13 Upgrade
Path](https://github.com/Kong/kong/blob/master/UPGRADE.md#upgrade-to-013x) for
more details regarding breaking changes and migrations before planning to
upgrade your Kong cluster.

### Breaking Changes

##### Configuration

- :warning: The `proxy_listen` and `admin_listen` configuration values have a
  new syntax. This syntax is more aligned with that of NGINX and is more
  powerful while also simpler. As a result, the following configuration values
  have been removed because superfluous: `ssl`, `admin_ssl`, `http2`,
  `admin_http2`, `proxy_listen_ssl`, and `admin_listen_ssl`.
  [#3147](https://github.com/Kong/kong/pull/3147)

##### Plugins

- :warning: galileo: As part of the Galileo deprecation path, the galileo
  plugin is not enabled by default anymore, although still bundled with 0.13.
  Users are advised to stop using the plugin, but for the time being can keep
  enabling it by adding it to the `custom_plugin` configuration value.
  [#3233](https://github.com/Kong/kong/pull/3233)
- :warning: rate-limiting (Cassandra): The default migration for including
  Routes and Services in plugins will remove and re-create the Cassandra
  rate-limiting counters table. This means that users that were rate-limited
  because of excessive API consumption will be able to consume the API until
  they reach their limit again. There is no such data deletion in PosgreSQL.
  [def201f](https://github.com/Kong/kong/commit/def201f566ccf2dd9b670e2f38e401a0450b1cb5)

### Changes

##### Dependencies

- **Note to Docker users**: The `latest` tag on Docker Hub now points to the
  **alpine** image instead of CentOS. This also applies to the `0.13.0` tag.
- The OpenResty version shipped with our default packages has been bumped to
  `1.13.6.1`. The 0.13.0 release should still be compatible with the OpenResty
  `1.11.2.x` series for the time being.
- Bumped [lua-resty-dns-client](https://github.com/Kong/lua-resty-dns-client)
  to `2.0.0`.
  [#3220](https://github.com/Kong/kong/pull/3220)
- Bumped [lua-resty-http](https://github.com/pintsized/lua-resty-http) to
  `0.12`.
  [#3196](https://github.com/Kong/kong/pull/3196)
- Bumped [lua-multipart](https://github.com/Kong/lua-multipart) to `0.5.5`.
  [#3318](https://github.com/Kong/kong/pull/3318)
- Bumped [lua-resty-healthcheck](https://github.com/Kong/lua-resty-healthcheck)
  to `0.4.0`.
  [#3321](https://github.com/Kong/kong/pull/3321)

### Additions

##### Configuration

- :fireworks: Support for **control-plane** and **data-plane** modes. The new
  syntax of `proxy_listen` and `admin_listen` supports `off`, which
  disables either one of those interfaces. It is now simpler than ever to
  make a Kong node "Proxy only" (data-plane) or "Admin only" (control-plane).
  [#3147](https://github.com/Kong/kong/pull/3147)

##### Core

- :fireworks: This release introduces two new entities: **Routes** and
  **Services**. Those entities will provide a better separation of concerns
  than the "API" entity offers. Routes will define rules for matching a
  client's request (e.g., method, host, path...), and Services will represent
  upstream services (or backends) that Kong should proxy those requests to.
  Plugins can also be added to both Routes and Services, enabling use-cases to
  apply plugins more granularly (e.g., per endpoint).
  Following this addition, the API entity and related Admin API endpoints are
  now deprecated. This release is backwards-compatible with the previous model
  and all of your currently defined APIs and matching rules are still
  supported, although we advise users to migrate to Routes and Services as soon
  as possible.
  [#3224](https://github.com/Kong/kong/pull/3224)

##### Admin API

- :fireworks: New endpoints: `/routes` and `/services` to interact with the new
  core entities. More specific endpoints are also available such as
  `/services/{service id or name}/routes`,
  `/services/{service id or name}/plugins`, and `/routes/{route id}/plugins`.
  [#3224](https://github.com/Kong/kong/pull/3224)
- :fireworks: Our new endpoints (listed above) provide much better responses
  with regards to producing responses for incomplete entities, errors, etc...
  In the future, existing endpoints will gradually be moved to using this new
  Admin API content producer.
  [#3224](https://github.com/Kong/kong/pull/3224)
- :fireworks: Improved argument parsing in form-urlencoded requests to the new
  endpoints as well.
  Kong now expects the following syntaxes for representing
  arrays: `hosts[]=a.com&hosts[]=b.com`, `hosts[1]=a.com&hosts[2]=b.com`, which
  avoid comma-separated arrays and related issues that can arise.
  In the future, existing endpoints will gradually be moved to using this new
  Admin API content parser.
  [#3224](https://github.com/Kong/kong/pull/3224)

##### Plugins

- jwt: `ngx.ctx.authenticated_jwt_token` is available for other plugins to use.
  [#2988](https://github.com/Kong/kong/pull/2988)
- statsd: The fields `host`, `port` and `metrics` are no longer marked as
  "required", since they have a default value.
  [#3209](https://github.com/Kong/kong/pull/3209)

### Fixes

##### Core

- Fix an issue causing nodes in a cluster to use the default health checks
  configuration when the user configured them from another node (event
  propagated via the cluster).
  [#3319](https://github.com/Kong/kong/pull/3319)
- Increase the default load balancer wheel size from 100 to 10.000. This allows
  for a better distribution of the load between Targets in general.
  [#3296](https://github.com/Kong/kong/pull/3296)

##### Admin API

- Fix several issues with application/multipart MIME type parsing of payloads.
  [#3318](https://github.com/Kong/kong/pull/3318)
- Fix several issues with the parsing of health checks configuration values.
  [#3306](https://github.com/Kong/kong/pull/3306)
  [#3321](https://github.com/Kong/kong/pull/3321)

[Back to TOC](#table-of-contents)

## [0.12.3] - 2018/03/12

### Fixed

- Suppress a memory leak in the core introduced in 0.12.2.
  Thanks [@mengskysama](https://github.com/mengskysama) for the report.
  [#3278](https://github.com/Kong/kong/pull/3278)

[Back to TOC](#table-of-contents)

## [0.12.2] - 2018/02/28

### Added

##### Core

- Load balancers now log DNS errors to facilitate debugging.
  [#3177](https://github.com/Kong/kong/pull/3177)
- Reports now can include custom immutable values.
  [#3180](https://github.com/Kong/kong/pull/3180)

##### CLI

- The `kong migrations reset` command has a new `--yes` flag. This flag makes
  the command run non-interactively, and ensures no confirmation prompt will
  occur.
  [#3189](https://github.com/Kong/kong/pull/3189)

##### Admin API

- A new endpoint `/upstreams/:upstream_id/health` will return the health of the
  specified upstream.
  [#3232](https://github.com/Kong/kong/pull/3232)
- The `/` endpoint in the Admin API now exposes the `node_id` field.
  [#3234](https://github.com/Kong/kong/pull/3234)

### Fixed

##### Core

- HTTP/1.0 requests without a Host header are routed instead of being rejected.
  HTTP/1.1 requests without a Host are considered invalid and will still be
  rejected.
  Thanks to [@rainiest](https://github.com/rainest) for the patch!
  [#3216](https://github.com/Kong/kong/pull/3216)
- Fix the load balancer initialization when some Targets would contain
  hostnames.
  [#3187](https://github.com/Kong/kong/pull/3187)
- Fix incomplete handling of errors when initializing DAO objects.
  [637532e](https://github.com/Kong/kong/commit/637532e05d8ed9a921b5de861cc7f463e96c6e04)
- Remove bogus errors in the logs provoked by healthcheckers between the time
  they are unregistered and the time they are garbage-collected
  ([#3207](https://github.com/Kong/kong/pull/3207)) and when receiving an HTTP
  status not tracked by healthy or unhealthy lists
  ([c8eb5ae](https://github.com/Kong/kong/commit/c8eb5ae28147fc02473c05a7b1dbf502fbb64242)).
- Fix soft errors not being handled correctly inside the Kong cache.
  [#3150](https://github.com/Kong/kong/pull/3150)

##### Migrations

- Better handling of already existing Cassandra keyspaces in migrations.
  [#3203](https://github.com/Kong/kong/pull/3203).
  Thanks to [@pamiel](https://github.com/pamiel) for the patch!

##### Admin API

- Ensure `GET /certificates/{uuid}` does not return HTTP 500 when the given
  identifier does not exist.
  Thanks to [@vdesjardins](https://github.com/vdesjardins) for the patch!
  [#3148](https://github.com/Kong/kong/pull/3148)

[Back to TOC](#table-of-contents)

## [0.12.1] - 2018/01/18

This release addresses a few issues encountered with 0.12.0, including one
which would prevent upgrading from a previous version. The [0.12 Upgrade
Path](https://github.com/Kong/kong/blob/master/UPGRADE.md)
is still relevant for upgrading existing clusters to 0.12.1.

### Fixed

- Fix a migration between previous Kong versions and 0.12.0.
  [#3159](https://github.com/Kong/kong/pull/3159)
- Ensure Lua errors are propagated when thrown in the `access` handler by
  plugins.
  [38580ff](https://github.com/Kong/kong/commit/38580ff547cbd4a557829e3ad135cd6a0f821f7c)

[Back to TOC](#table-of-contents)

## [0.12.0] - 2018/01/16

This major release focuses on two new features we are very excited about:
**health checks** and **hash based load balancing**!

We also took this as an opportunity to fix a few prominent issues, sometimes
at the expense of breaking changes but overall improving the flexibility and
usability of Kong! Do keep in mind that this is a major release, and as such,
that we require of you to run the **migrations step**, via the
`kong migrations up` command.

Please take a few minutes to thoroughly read the [0.12 Upgrade
Path](https://github.com/Kong/kong/blob/master/UPGRADE.md#upgrade-to-012x)
for more details regarding breaking changes and migrations before planning to
upgrade your Kong cluster.

### Deprecation notices

Starting with 0.12.0, we are announcing the deprecation of older versions
of our supported databases:

- Support for PostgreSQL 9.4 is deprecated. Users are advised to upgrade to
  9.5+
- Support for Cassandra 2.1 and below is deprecated. Users are advised to
  upgrade to 2.2+

Note that the above deprecated versions are still supported in this release,
but will be dropped in subsequent ones.

### Breaking changes

##### Core

- :warning: The required OpenResty version has been bumped to 1.11.2.5. If you
  are installing Kong from one of our distribution packages, you are not
  affected by this change.
  [#3097](https://github.com/Kong/kong/pull/3097)
- :warning: As Kong now executes subsequent plugins when a request is being
  short-circuited (e.g. HTTP 401 responses from auth plugins), plugins that
  run in the header or body filter phases will be run upon such responses
  from the access phase. We consider this change a big improvement in the
  Kong run-loop as it allows for more flexibility for plugins. However, it is
  unlikely, but possible that some of these plugins (e.g. your custom plugins)
  now run in scenarios where they were not previously expected to run.
  [#3079](https://github.com/Kong/kong/pull/3079)

##### Admin API

- :warning: By default, the Admin API now only listens on the local interface.
  We consider this change to be an improvement in the default security policy
  of Kong. If you are already using Kong, and your Admin API still binds to all
  interfaces, consider updating it as well. You can do so by updating the
  `admin_listen` configuration value, like so: `admin_listen = 127.0.0.1:8001`.
  Thanks [@pduldig-at-tw](https://github.com/pduldig-at-tw) for the suggestion
  and the patch.
  [#3016](https://github.com/Kong/kong/pull/3016)

  :red_circle: **Note to Docker users**: Beware of this change as you may have
  to ensure that your Admin API is reachable via the host's interface.
  You can use the `-e KONG_ADMIN_LISTEN` argument when provisioning your
  container(s) to update this value; for example,
  `-e KONG_ADMIN_LISTEN=0.0.0.0:8001`.

- :warning: To reduce confusion, the `/upstreams/:upstream_name_or_id/targets/`
  has been updated to not show the full list of Targets anymore, but only
  the ones that are currently active in the load balancer. To retrieve the full
  history of Targets, you can now query
  `/upstreams/:upstream_name_or_id/targets/all`. The
  `/upstreams/:upstream_name_or_id/targets/active` endpoint has been removed.
  Thanks [@hbagdi](https://github.com/hbagdi) for tackling this backlog item!
  [#3049](https://github.com/Kong/kong/pull/3049)
- :warning: The `orderlist` property of Upstreams has been removed, along with
  any confusion it may have brought. The balancer is now able to fully function
  without it, yet with the same level of entropy in its load distribution.
  [#2748](https://github.com/Kong/kong/pull/2748)

##### CLI

- :warning: The `$ kong compile` command which was deprecated in 0.11.0 has
  been removed.
  [#3069](https://github.com/Kong/kong/pull/3069)

##### Plugins

- :warning: In logging plugins, the `request.request_uri` field has been
  renamed to `request.url`.
  [#2445](https://github.com/Kong/kong/pull/2445)
  [#3098](https://github.com/Kong/kong/pull/3098)

### Added

##### Core

- :fireworks: Support for **health checks**! Kong can now short-circuit some
  of your upstream Targets (replicas) from its load balancer when it encounters
  too many TCP or HTTP errors. You can configure the number of failures, or the
  HTTP status codes that should be considered invalid, and Kong will monitor
  the failures and successes of proxied requests to each upstream Target. We
  call this feature **passive health checks**.
  Additionally, you can configure **active health checks**, which will make
  Kong perform periodic HTTP test requests to actively monitor the health of
  your upstream services, and pre-emptively short-circuit them.
  Upstream Targets can be manually taken up or down via two new Admin API
  endpoints: `/healthy` and `/unhealthy`.
  [#3096](https://github.com/Kong/kong/pull/3096)
- :fireworks: Support for **hash based load balancing**! Kong now offers
  consistent hashing/sticky sessions load balancing capabilities via the new
  `hash_*` attributes of the Upstream entity. Hashes can be based off client
  IPs, request headers, or Consumers!
  [#2875](https://github.com/Kong/kong/pull/2875)
- :fireworks: Logging plugins now log requests that were short-circuited by
  Kong! (e.g. HTTP 401 responses from auth plugins or HTTP 429 responses from
  rate limiting plugins, etc.) Kong now executes any subsequent plugins once a
  request has been short-circuited. Your plugin must be using the
  `kong.tools.responses` module for this behavior to be respected.
  [#3079](https://github.com/Kong/kong/pull/3079)
- Kong is now compatible with OpenResty up to version 1.13.6.1. Be aware that
  the recommended (and default) version shipped with this release is still
  1.11.2.5.
  [#3070](https://github.com/Kong/kong/pull/3070)

##### CLI

- `$ kong start` now considers the commonly used `/opt/openresty` prefix when
  searching for the `nginx` executable.
  [#3074](https://github.com/Kong/kong/pull/3074)

##### Admin API

- Two new endpoints, `/healthy` and `/unhealthy` can be used to manually bring
  upstream Targets up or down, as part of the new health checks feature of the
  load balancer.
  [#3096](https://github.com/Kong/kong/pull/3096)

##### Plugins

- logging plugins: A new field `upstream_uri` now logs the value of the
  upstream request's path. This is useful to help debugging plugins or setups
  that aim at rewriting a request's URL during proxying.
  Thanks [@shiprabehera](https://github.com/shiprabehera) for the patch!
  [#2445](https://github.com/Kong/kong/pull/2445)
- tcp-log: Support for TLS handshake with the logs recipients for secure
  transmissions of logging data.
  [#3091](https://github.com/Kong/kong/pull/3091)
- jwt: Support for JWTs passed in cookies. Use the new `config.cookie_names`
  property to configure the behavior to your liking.
  Thanks [@mvanholsteijn](https://github.com/mvanholsteijn) for the patch!
  [#2974](https://github.com/Kong/kong/pull/2974)
- oauth2
    - New `config.auth_header_name` property to customize the authorization
      header's name.
      Thanks [@supraja93](https://github.com/supraja93)
      [#2928](https://github.com/Kong/kong/pull/2928)
    - New `config.refresh_ttl` property to customize the TTL of refresh tokens,
      previously hard-coded to 14 days.
      Thanks [@bob983](https://github.com/bob983) for the patch!
      [#2942](https://github.com/Kong/kong/pull/2942)
    - Avoid an error in the logs when trying to retrieve an access token from
      a request without a body.
      Thanks [@WALL-E](https://github.com/WALL-E) for the patch.
      [#3063](https://github.com/Kong/kong/pull/3063)
- ldap: New `config.header_type` property to customize the authorization method
  in the `Authorization` header.
  Thanks [@francois-maillard](https://github.com/francois-maillard) for the
  patch!
  [#2963](https://github.com/Kong/kong/pull/2963)

### Fixed

##### CLI

- Fix a potential vulnerability in which an attacker could read the Kong
  configuration file with insufficient permissions for a short window of time
  while Kong is being started.
  [#3057](https://github.com/Kong/kong/pull/3057)
- Proper log message upon timeout in `$ kong quit`.
  [#3061](https://github.com/Kong/kong/pull/3061)

##### Admin API

- The `/certificates` endpoint now properly supports the `snis` parameter
  in PUT and PATCH requests.
  Thanks [@hbagdi](https://github.com/hbagdi) for the contribution!
  [#3040](https://github.com/Kong/kong/pull/3040)
- Avoid sending the `HTTP/1.1 415 Unsupported Content Type` response when
  receiving a request with a valid `Content-Type`, but with an empty payload.
  [#3077](https://github.com/Kong/kong/pull/3077)

##### Plugins

- basic-auth:
    - Accept passwords containing `:`.
      Thanks [@nico-acidtango](https://github.com/nico-acidtango) for the patch!
      [#3014](https://github.com/Kong/kong/pull/3014)
    - Performance improvements, courtesy of
      [@nico-acidtango](https://github.com/nico-acidtango)
      [#3014](https://github.com/Kong/kong/pull/3014)

[Back to TOC](#table-of-contents)

## [0.11.2] - 2017/11/29

### Added

##### Plugins

- key-auth: New endpoints to manipulate API keys.
  Thanks [@hbagdi](https://github.com/hbagdi) for the contribution.
  [#2955](https://github.com/Kong/kong/pull/2955)
    - `/key-auths/` to paginate through all keys.
    - `/key-auths/:credential_key_or_id/consumer` to retrieve the Consumer
      associated with a key.
- basic-auth: New endpoints to manipulate basic-auth credentials.
  Thanks [@hbagdi](https://github.com/hbagdi) for the contribution.
  [#2998](https://github.com/Kong/kong/pull/2998)
    - `/basic-auths/` to paginate through all basic-auth credentials.
    - `/basic-auths/:credential_username_or_id/consumer` to retrieve the
      Consumer associated with a credential.
- jwt: New endpoints to manipulate JWTs.
  Thanks [@hbagdi](https://github.com/hbagdi) for the contribution.
  [#3003](https://github.com/Kong/kong/pull/3003)
    - `/jwts/` to paginate through all JWTs.
    - `/jwts/:jwt_key_or_id/consumer` to retrieve the Consumer
      associated with a JWT.
- hmac-auth: New endpoints to manipulate hmac-auth credentials.
  Thanks [@hbagdi](https://github.com/hbagdi) for the contribution.
  [#3009](https://github.com/Kong/kong/pull/3009)
    - `/hmac-auths/` to paginate through all hmac-auth credentials.
    - `/hmac-auths/:hmac_username_or_id/consumer` to retrieve the Consumer
      associated with a credential.
- acl: New endpoints to manipulate ACLs.
  Thanks [@hbagdi](https://github.com/hbagdi) for the contribution.
  [#3039](https://github.com/Kong/kong/pull/3039)
    - `/acls/` to paginate through all ACLs.
    - `/acls/:acl_id/consumer` to retrieve the Consumer
      associated with an ACL.

### Fixed

##### Core

- Avoid logging some unharmful error messages related to clustering.
  [#3002](https://github.com/Kong/kong/pull/3002)
- Improve performance and memory footprint when parsing multipart request
  bodies.
  [Kong/lua-multipart#13](https://github.com/Kong/lua-multipart/pull/13)

##### Configuration

- Add a format check for the `admin_listen_ssl` property, ensuring it contains
  a valid port.
  [#3031](https://github.com/Kong/kong/pull/3031)

##### Admin API

- PUT requests with payloads containing non-existing primary keys for entities
  now return HTTP 404 Not Found, instead of HTTP 200 OK without a response
  body.
  [#3007](https://github.com/Kong/kong/pull/3007)
- On the `/` endpoint, ensure `enabled_in_cluster` shows up as an empty JSON
  Array (`[]`), instead of an empty JSON Object (`{}`).
  Thanks [@hbagdi](https://github.com/hbagdi) for the patch!
  [#2982](https://github.com/Kong/kong/issues/2982)

##### Plugins

- hmac-auth: Better parsing of the `Authorization` header to avoid internal
  errors resulting in HTTP 500.
  Thanks [@mvanholsteijn](https://github.com/mvanholsteijn) for the patch!
  [#2996](https://github.com/Kong/kong/pull/2996)
- Improve the performance of the rate-limiting and response-rate-limiting
  plugins when using the Redis policy.
  [#2956](https://github.com/Kong/kong/pull/2956)
- Improve the performance of the response-transformer plugin.
  [#2977](https://github.com/Kong/kong/pull/2977)

## [0.11.1] - 2017/10/24

### Changed

##### Configuration

- Drop the `lua_code_cache` configuration property. This setting has been
  considered harmful since 0.11.0 as it interferes with Kong's internals.
  [#2854](https://github.com/Kong/kong/pull/2854)

### Fixed

##### Core

- DNS: SRV records pointing to an A record are now properly handled by the
  load balancer when `preserve_host` is disabled. Such records used to throw
  Lua errors on the proxy code path.
  [Kong/lua-resty-dns-client#19](https://github.com/Kong/lua-resty-dns-client/pull/19)
- Fixed an edge-case where `preserve_host` would sometimes craft an upstream
  request with a Host header from a previous client request instead of the
  current one.
  [#2832](https://github.com/Kong/kong/pull/2832)
- Ensure APIs with regex URIs are evaluated in the order that they are created.
  [#2924](https://github.com/Kong/kong/pull/2924)
- Fixed a typo that caused the load balancing components to ignore the Upstream
  slots property.
  [#2747](https://github.com/Kong/kong/pull/2747)

##### CLI

- Fixed the verification of self-signed SSL certificates for PostgreSQL and
  Cassandra in the `kong migrations` command. Self-signed SSL certificates are
  now properly verified during migrations according to the
  `lua_ssl_trusted_certificate` configuration property.
  [#2908](https://github.com/Kong/kong/pull/2908)

##### Admin API

- The `/upstream/{upstream}/targets/active` endpoint used to return HTTP
  `405 Method Not Allowed` when called with a trailing slash. Both notations
  (with and without the trailing slash) are now supported.
  [#2884](https://github.com/Kong/kong/pull/2884)

##### Plugins

- bot-detection: Fixed an issue which would prevent the plugin from running and
  result in an HTTP `500` error if configured globally.
  [#2906](https://github.com/Kong/kong/pull/2906)
- ip-restriction: Fixed support for the `0.0.0.0/0` CIDR block. This block is
  now supported and won't trigger an error when used in the `whitelist` or
  `blacklist` properties.
  [#2918](https://github.com/Kong/kong/pull/2918)

### Added

##### Plugins

- aws-lambda: Added support to forward the client request's HTTP method,
  headers, URI, and body to the Lambda function.
  [#2823](https://github.com/Kong/kong/pull/2823)
- key-auth: New `run_on_preflight` configuration option to control
  authentication on preflight requests.
  [#2857](https://github.com/Kong/kong/pull/2857)
- jwt: New `run_on_preflight` configuration option to control authentication
  on preflight requests.
  [#2857](https://github.com/Kong/kong/pull/2857)

##### Plugin development

- Ensure migrations have valid, unique names to avoid conflicts between custom
  plugins.
  Thanks [@ikogan](https://github.com/ikogan) for the patch!
  [#2821](https://github.com/Kong/kong/pull/2821)

### Improved

##### Migrations & Deployments

- Improve migrations reliability for future major releases.
  [#2869](https://github.com/Kong/kong/pull/2869)

##### Plugins

- Improve the performance of the acl and oauth2 plugins.
  [#2736](https://github.com/Kong/kong/pull/2736)
  [#2806](https://github.com/Kong/kong/pull/2806)

[Back to TOC](#table-of-contents)

## [0.10.4] - 2017/10/24

### Fixed

##### Core

- DNS: SRV records pointing to an A record are now properly handled by the
  load balancer when `preserve_host` is disabled. Such records used to throw
  Lua errors on the proxy code path.
  [Kong/lua-resty-dns-client#19](https://github.com/Kong/lua-resty-dns-client/pull/19)
- HTTP `400` errors thrown by Nginx are now correctly caught by Kong and return
  a native, Kong-friendly response.
  [#2476](https://github.com/Mashape/kong/pull/2476)
- Fix an edge-case where an API with multiple `uris` and `strip_uri = true`
  would not always strip the client URI.
  [#2562](https://github.com/Mashape/kong/issues/2562)
- Fix an issue where Kong would match an API with a shorter URI (from its
  `uris` value) as a prefix instead of a longer, matching prefix from
  another API.
  [#2662](https://github.com/Mashape/kong/issues/2662)
- Fixed a typo that caused the load balancing components to ignore the
  Upstream `slots` property.
  [#2747](https://github.com/Mashape/kong/pull/2747)

##### Configuration

- Octothorpes (`#`) can now be escaped (`\#`) and included in the Kong
  configuration values such as your datastore passwords or usernames.
  [#2411](https://github.com/Mashape/kong/pull/2411)

##### Admin API

- The `data` response field of the `/upstreams/{upstream}/targets/active`
  Admin API endpoint now returns a list (`[]`) instead of an object (`{}`)
  when no active targets are present.
  [#2619](https://github.com/Mashape/kong/pull/2619)

##### Plugins

- datadog: Avoid a runtime error if the plugin is configured as a global plugin
  but the downstream request did not match any configured API.
  Thanks [@kjsteuer](https://github.com/kjsteuer) for the fix!
  [#2702](https://github.com/Mashape/kong/pull/2702)
- ip-restriction: Fixed support for the `0.0.0.0/0` CIDR block. This block is
  now supported and won't trigger an error when used in the `whitelist` or
  `blacklist` properties.
  [#2918](https://github.com/Mashape/kong/pull/2918)

[Back to TOC](#table-of-contents)

## [0.11.0] - 2017/08/16

The latest and greatest version of Kong features improvements all over the
board for a better and easier integration with your infrastructure!

The highlights of this release are:

- Support for **regex URIs** in routing, one of the oldest requested
  features from the community.
- Support for HTTP/2 traffic from your clients.
- Kong does not depend on Serf anymore, which makes deployment and networking
  requirements **considerably simpler**.
- A better integration with orchestration tools thanks to the support for **non
  FQDNs** in Kong's DNS resolver.

As per usual, our major releases include datastore migrations which are
considered **breaking changes**. Additionally, this release contains numerous
breaking changes to the deployment process and proxying behavior that you
should be familiar with.

We strongly advise that you read this changeset thoroughly, as well as the
[0.11 Upgrade Path](https://github.com/Kong/kong/blob/master/UPGRADE.md#upgrade-to-011x)
if you are planning to upgrade a Kong cluster.

### Breaking changes

##### Configuration

- :warning: Numerous updates were made to the Nginx configuration template.
  If you are using a custom template, you **must** apply those
  modifications. See the [0.11 Upgrade
  Path](https://github.com/Kong/kong/blob/master/UPGRADE.md#upgrade-to-011x)
  for a complete list of changes to apply.

##### Migrations & Deployment

- :warning: Migrations are **not** executed automatically by `kong start`
  anymore. Migrations are now a **manual** process, which must be executed via
  the `kong migrations` command. In practice, this means that you have to run
  `kong migrations up [-c kong.conf]` in one of your nodes **before** starting
  your Kong nodes. This command should be run from a **single** node/container
  to avoid several nodes running migrations concurrently and potentially
  corrupting your database. Once the migrations are up-to-date, it is
  considered safe to start multiple Kong nodes concurrently.
  [#2421](https://github.com/Kong/kong/pull/2421)
- :warning: :fireworks: Serf is **not** a dependency anymore. Kong nodes now
  handle cache invalidation events via a built-in database polling mechanism.
  See the new "Datastore Cache" section of the configuration file which
  contains 3 new documented properties: `db_update_frequency`,
  `db_update_propagation`, and `db_cache_ttl`. If you are using Cassandra, you
  **should** pay a particular attention to the `db_update_propagation` setting,
  as you **should not** use the default value of `0`.
  [#2561](https://github.com/Kong/kong/pull/2561)

##### Core

- :warning: Kong now requires OpenResty `1.11.2.4`. OpenResty's LuaJIT can
  now be built with Lua 5.2 compatibility.
  [#2489](https://github.com/Kong/kong/pull/2489)
  [#2790](https://github.com/Kong/kong/pull/2790)
- :warning: Previously, the `X-Forwarded-*` and `X-Real-IP` headers were
  trusted from any client by default, and forwarded upstream. With the
  introduction of the new `trusted_ips` property (see the below "Added"
  section) and to enforce best security practices, Kong *does not* trust
  any client IP address by default anymore. This will make Kong *not*
  forward incoming `X-Forwarded-*` headers if not coming from configured,
  trusted IP addresses blocks. This setting also affects the API
  `check_https` field, which itself relies on *trusted* `X-Forwarded-Proto`
  headers **only**.
  [#2236](https://github.com/Kong/kong/pull/2236)
- :warning: The API Object property `http_if_terminated` is now set to `false`
  by default. For Kong to evaluate the client `X-Forwarded-Proto` header, you
  must now configure Kong to trust the client IP (see above change), **and**
  you must explicitly set this value to `true`. This affects you if you are
  doing SSL termination somewhere before your requests hit Kong, and if you
  have configured `https_only` on the API, or if you use a plugin that requires
  HTTPS traffic (e.g. OAuth2).
  [#2588](https://github.com/Kong/kong/pull/2588)
- :warning: The internal DNS resolver now honours the `search` and `ndots`
  configuration options of your `resolv.conf` file. Make sure that DNS
  resolution is still consistent in your environment, and consider
  eventually not using FQDNs anymore.
  [#2425](https://github.com/Kong/kong/pull/2425)

##### Admin API

- :warning: As a result of the Serf removal, Kong is now entirely stateless,
  and as such, the `/cluster` endpoint has disappeared.
  [#2561](https://github.com/Kong/kong/pull/2561)
- :warning: The Admin API `/status` endpoint does not return a count of the
  database entities anymore. Instead, it now returns a `database.reachable`
  boolean value, which reflects the state of the connection between Kong
  and the underlying database. Please note that this flag **does not**
  reflect the health of the database itself.
  [#2567](https://github.com/Kong/kong/pull/2567)

##### Plugin development

- :warning: The upstream URI is now determined via the Nginx
  `$upstream_uri` variable. Custom plugins using the `ngx.req.set_uri()`
  API will not be taken into consideration anymore. One must now set the
  `ngx.var.upstream_uri` variable from the Lua land.
  [#2519](https://github.com/Kong/kong/pull/2519)
- :warning: The `hooks.lua` module for custom plugins is dropped, along
  with the `database_cache.lua` module. Database entities caching and
  eviction has been greatly improved to simplify and automate most caching
  use-cases. See the [Plugins Development
  Guide](https://getkong.org/docs/0.11.x/plugin-development/entities-cache/)
  and the [0.11 Upgrade
  Path](https://github.com/Kong/kong/blob/master/UPGRADE.md#upgrade-to-011x)
  for more details.
  [#2561](https://github.com/Kong/kong/pull/2561)
- :warning: To ensure that the order of execution of plugins is still the same
  for vanilla Kong installations, we had to update the `PRIORITY` field of some
  of our bundled plugins. If your custom plugin must run after or before a
  specific bundled plugin, you might have to update your plugin's `PRIORITY`
  field as well. The complete list of plugins and their priorities is available
  on the [Plugins Development
  Guide](https://getkong.org/docs/0.11.x/plugin-development/custom-logic/).
  [#2489](https://github.com/Kong/kong/pull/2489)
  [#2813](https://github.com/Kong/kong/pull/2813)

### Deprecated

##### CLI

- The `kong compile` command has been deprecated. Instead, prefer using
  the new `kong prepare` command.
  [#2706](https://github.com/Kong/kong/pull/2706)

### Changed

##### Core

- Performance around DNS resolution has been greatly improved in some
  cases.
  [#2625](https://github.com/Kong/kong/pull/2425)
- Secret values are now generated with a kernel-level, Cryptographically
  Secure PRNG.
  [#2536](https://github.com/Kong/kong/pull/2536)
- The `.kong_env` file created by Kong in its running prefix is now written
  without world-read permissions.
  [#2611](https://github.com/Kong/kong/pull/2611)

##### Plugin development

- The `marshall_event` function on schemas is now ignored by Kong, and can be
  safely removed as the new cache invalidation mechanism natively handles
  safer events broadcasting.
  [#2561](https://github.com/Kong/kong/pull/2561)

### Added

##### Core

- :fireworks: Support for regex URIs! You can now define regexes in your
  APIs `uris` property. Those regexes can have capturing groups which can
  be extracted by Kong during a request, and accessed later in the plugins
  (useful for URI rewriting). See the [Proxy
  Guide](https://getkong.org/docs/0.11.x/proxy/#using-regexes-in-uris) for
  documentation on how to use regex URIs.
  [#2681](https://github.com/Kong/kong/pull/2681)
- :fireworks: Support for HTTP/2. A new `http2` directive now enables
  HTTP/2 traffic on the `proxy_listen_ssl` address.
  [#2541](https://github.com/Kong/kong/pull/2541)
- :fireworks: Support for the `search` and `ndots` configuration options of
  your `resolv.conf` file.
  [#2425](https://github.com/Kong/kong/pull/2425)
- Kong now forwards new headers to your upstream services:
  `X-Forwarded-Host`, `X-Forwarded-Port`, and `X-Forwarded-Proto`.
  [#2236](https://github.com/Kong/kong/pull/2236)
- Support for the PROXY protocol. If the new `real_ip_header` configuration
  property is set to `real_ip_header = proxy_protocol`, then Kong will
  append the `proxy_protocol` parameter to the Nginx `listen` directive of
  the Kong proxy port.
  [#2236](https://github.com/Kong/kong/pull/2236)
- Support for BDR compatibility in the PostgreSQL migrations.
  Thanks [@AlexBloor](https://github.com/AlexBloor) for the patch!
  [#2672](https://github.com/Kong/kong/pull/2672)

##### Configuration

- Support for DNS nameservers specified in IPv6 format.
  [#2634](https://github.com/Kong/kong/pull/2634)
- A few new DNS configuration properties allow you to tweak the Kong DNS
  resolver, and in particular, how it handles the resolution of different
  record types or the eviction of stale records.
  [#2625](https://github.com/Kong/kong/pull/2625)
- A new `trusted_ips` configuration property allows you to define a list of
  trusted IP address blocks that are known to send trusted `X-Forwarded-*`
  headers. Requests from trusted IPs will make Kong forward those headers
  upstream. Requests from non-trusted IP addresses will make Kong override
  the `X-Forwarded-*` headers with its own values. In addition, this
  property also sets the ngx_http_realip_module `set_real_ip_from`
  directive(s), which makes Kong trust the incoming `X-Real-IP` header as
  well, which is used for operations such as rate-limiting by IP address,
  and that Kong forwards upstream as well.
  [#2236](https://github.com/Kong/kong/pull/2236)
- You can now configure the ngx_http_realip_module from the Kong
  configuration.  In addition to `trusted_ips` which sets the
  `set_real_ip_from` directives(s), two new properties, `real_ip_header`
  and `real_ip_recursive` allow you to configure the ngx_http_realip_module
  directives bearing the same name.
  [#2236](https://github.com/Kong/kong/pull/2236)
- Ability to hide Kong-specific response headers. Two new configuration
  fields: `server_tokens` and `latency_tokens` will respectively toggle
  whether the `Server` and `X-Kong-*-Latency` headers should be sent to
  downstream clients.
  [#2259](https://github.com/Kong/kong/pull/2259)
- New configuration property to tune handling request body data via the
  `client_max_body_size` and `client_body_buffer_size` directives
  (mirroring their Nginx counterparts). Note these settings are only
  defined for proxy requests; request body handling in the Admin API
  remains unchanged.
  [#2602](https://github.com/Kong/kong/pull/2602)
- New `error_default_type` configuration property. This setting is to
  specify a MIME type that will be used as the error response body format
  when Nginx encounters an error, but no `Accept` header was present in the
  request. The default value is `text/plain` for backwards compatibility.
  Thanks [@therealgambo](https://github.com/therealgambo) for the
  contribution!
  [#2500](https://github.com/Kong/kong/pull/2500)
- New `nginx_user` configuration property, which interfaces with the Nginx
  `user` directive.
  Thanks [@depay](https://github.com/depay) for the contribution!
  [#2180](https://github.com/Kong/kong/pull/2180)

##### CLI

- New `kong prepare` command to prepare the Kong running prefix (creating
  log files, SSL certificates, etc...) and allow for Kong to be started via
  the `nginx` binary. This is useful for environments like containers,
  where the foreground process should be the Nginx master process. The
  `kong compile` command has been deprecated as a result of this addition.
  [#2706](https://github.com/Kong/kong/pull/2706)

##### Admin API

- Ability to retrieve plugins added to a Consumer via two new endpoints:
  `/consumers/:username_or_id/plugins/` and
  `/consumers/:username_or_id/plugins/:plugin_id`.
  [#2714](https://github.com/Kong/kong/pull/2714)
- Support for JSON `null` in `PATCH` requests to unset a value on any
  entity.
  [#2700](https://github.com/Kong/kong/pull/2700)

##### Plugins

- jwt: Support for RS512 signed tokens.
  Thanks [@sarraz1](https://github.com/sarraz1) for the patch!
  [#2666](https://github.com/Kong/kong/pull/2666)
- rate-limiting/response-ratelimiting: Optionally hide informative response
  headers.
  [#2087](https://github.com/Kong/kong/pull/2087)
- aws-lambda: Define a custom response status when the upstream
  `X-Amz-Function-Error` header is "Unhandled".
  Thanks [@erran](https://github.com/erran) for the contribution!
  [#2587](https://github.com/Kong/kong/pull/2587)
- aws-lambda: Add new AWS regions that were previously unsupported.
  [#2769](https://github.com/Kong/kong/pull/2769)
- hmac: New option to validate the client-provided SHA-256 of the request
  body.
  Thanks [@vaibhavatul47](https://github.com/vaibhavatul47) for the
  contribution!
  [#2419](https://github.com/Kong/kong/pull/2419)
- hmac: Added support for `enforce_headers` option and added HMAC-SHA256,
  HMAC-SHA384, and HMAC-SHA512 support.
  [#2644](https://github.com/Kong/kong/pull/2644)
- statsd: New metrics and more flexible configuration. Support for
  prefixes, configurable stat type, and added metrics.
  [#2400](https://github.com/Kong/kong/pull/2400)
- datadog: New metrics and more flexible configuration. Support for
  prefixes, configurable stat type, and added metrics.
  [#2394](https://github.com/Kong/kong/pull/2394)

### Fixed

##### Core

- Kong now ensures that your clients URIs are transparently proxied
  upstream.  No percent-encoding/decoding or querystring stripping will
  occur anymore.
  [#2519](https://github.com/Kong/kong/pull/2519)
- Fix an issue where Kong would match an API with a shorter URI (from its
  `uris` value) as a prefix instead of a longer, matching prefix from
  another API.
  [#2662](https://github.com/Kong/kong/issues/2662)
- Fix an edge-case where an API with multiple `uris` and `strip_uri = true`
  would not always strip the client URI.
  [#2562](https://github.com/Kong/kong/issues/2562)
- HTTP `400` errors thrown by Nginx are now correctly caught by Kong and return
  a native, Kong-friendly response.
  [#2476](https://github.com/Kong/kong/pull/2476)

##### Configuration

- Octothorpes (`#`) can now be escaped (`\#`) and included in the Kong
  configuration values such as your datastore passwords or usernames.
  [#2411](https://github.com/Kong/kong/pull/2411)

##### Admin API

- The `data` response field of the `/upstreams/{upstream}/targets/active`
  Admin API endpoint now returns a list (`[]`) instead of an object (`{}`)
  when no active targets are present.
  [#2619](https://github.com/Kong/kong/pull/2619)

##### Plugins

- The `unique` constraint on OAuth2 `client_secrets` has been removed.
  [#2447](https://github.com/Kong/kong/pull/2447)
- The `unique` constraint on JWT Credentials `secrets` has been removed.
  [#2548](https://github.com/Kong/kong/pull/2548)
- oauth2: When requesting a token from `/oauth2/token`, one can now pass the
  `client_id` as a request body parameter, while `client_id:client_secret` is
  passed via the Authorization header. This allows for better integration
  with some OAuth2 flows proposed out there, such as from Cloudflare Apps.
  Thanks [@cedum](https://github.com/cedum) for the patch!
  [#2577](https://github.com/Kong/kong/pull/2577)
- datadog: Avoid a runtime error if the plugin is configured as a global plugin
  but the downstream request did not match any configured API.
  Thanks [@kjsteuer](https://github.com/kjsteuer) for the fix!
  [#2702](https://github.com/Kong/kong/pull/2702)
- Logging plugins: the produced logs `latencies.kong` field used to omit the
  time Kong spent in its Load Balancing logic, which includes DNS resolution
  time. This latency is now included in `latencies.kong`.
  [#2494](https://github.com/Kong/kong/pull/2494)

[Back to TOC](#table-of-contents)

## [0.10.3] - 2017/05/24

### Changed

- We noticed that some distribution packages were not
  building OpenResty against a JITable PCRE library. This
  happened on Ubuntu and RHEL environments where OpenResty was
  built against the system's PCRE installation.
  We now compile OpenResty against a JITable PCRE source for
  those platforms, which should result in significant performance
  improvements in regex matching.
  [Mashape/kong-distributions #9](https://github.com/Kong/kong-distributions/pull/9)
- TLS connections are now handled with a modern list of
  accepted ciphers, as per the Mozilla recommended TLS
  ciphers list.
  See https://wiki.mozilla.org/Security/Server_Side_TLS.
  This behavior is configurable via the newly
  introduced configuration properties described in the
  below "Added" section.
- Plugins:
  - rate-limiting: Performance improvements when using the
    `cluster` policy. The number of round trips to the
    database has been limited to the number of configured
    limits.
    [#2488](https://github.com/Kong/kong/pull/2488)

### Added

- New `ssl_cipher_suite` and `ssl_ciphers` configuration
  properties to configure the desired set of accepted ciphers,
  based on the Mozilla recommended TLS ciphers list.
  [#2555](https://github.com/Kong/kong/pull/2555)
- New `proxy_ssl_certificate` and `proxy_ssl_certificate_key`
  configuration properties. These properties configure the
  Nginx directives bearing the same name, to set client
  certificates to Kong when connecting to your upstream services.
  [#2556](https://github.com/Kong/kong/pull/2556)
- Proxy and Admin API access and error log paths are now
  configurable. Access logs can be entirely disabled if
  desired.
  [#2552](https://github.com/Kong/kong/pull/2552)
- Plugins:
  - Logging plugins: The produced logs include a new `tries`
    field which contains, which includes the upstream
    connection successes and failures of the load-balancer.
    [#2429](https://github.com/Kong/kong/pull/2429)
  - key-auth: Credentials can now be sent in the request body.
    [#2493](https://github.com/Kong/kong/pull/2493)
  - cors: Origins can now be defined as regular expressions.
    [#2482](https://github.com/Kong/kong/pull/2482)

### Fixed

- APIs matching: prioritize APIs with longer `uris` when said
  APIs also define `hosts` and/or `methods` as well. Thanks
  [@leonzz](https://github.com/leonzz) for the patch.
  [#2523](https://github.com/Kong/kong/pull/2523)
- SSL connections to Cassandra can now properly verify the
  certificate in use (when `cassandra_ssl_verify` is enabled).
  [#2531](https://github.com/Kong/kong/pull/2531)
- The DNS resolver no longer sends a A or AAAA DNS queries for SRV
  records. This should improve performance by avoiding unnecessary
  lookups.
  [#2563](https://github.com/Kong/kong/pull/2563) &
  [Mashape/lua-resty-dns-client #12](https://github.com/Kong/lua-resty-dns-client/pull/12)
- Plugins
  - All authentication plugins don't throw an error anymore when
    invalid credentials are given and the `anonymous` user isn't
    configured.
    [#2508](https://github.com/Kong/kong/pull/2508)
  - rate-limiting: Effectively use the desired Redis database when
    the `redis` policy is in use and the `config.redis_database`
    property is set.
    [#2481](https://github.com/Kong/kong/pull/2481)
  - cors: The regression introduced in 0.10.1 regarding not
    sending the `*` wildcard when `conf.origin` was not specified
    has been fixed.
    [#2518](https://github.com/Kong/kong/pull/2518)
  - oauth2: properly check the client application ownership of a
    token before refreshing it.
    [#2461](https://github.com/Kong/kong/pull/2461)

[Back to TOC](#table-of-contents)

## [0.10.2] - 2017/05/01

### Changed

- The Kong DNS resolver now honors the `MAXNS` setting (3) when parsing the
  nameservers specified in `resolv.conf`.
  [#2290](https://github.com/Kong/kong/issues/2290)
- Kong now matches incoming requests via the `$request_uri` property, instead
  of `$uri`, in order to better handle percent-encoded URIS. A more detailed
  explanation will be included in the below "Fixed" section.
  [#2377](https://github.com/Kong/kong/pull/2377)
- Upstream calls do not unconditionally include a trailing `/` anymore. See the
  below "Added" section for more details.
  [#2315](https://github.com/Kong/kong/pull/2315)
- Admin API:
  - The "active targets" endpoint now only return the most recent nonzero
    weight Targets, instead of all nonzero weight targets. This is to provide
    a better picture of the Targets currently in use by the Kong load balancer.
    [#2310](https://github.com/Kong/kong/pull/2310)

### Added

- :fireworks: Plugins can implement a new `rewrite` handler to execute code in
  the Nginx rewrite phase. This phase is executed prior to matching a
  registered Kong API, and prior to any authentication plugin. As such, only
  global plugins (neither tied to an API or Consumer) will execute this phase.
  [#2354](https://github.com/Kong/kong/pull/2354)
- Ability for the client to chose whether the upstream request (Kong <->
  upstream) should contain a trailing slash in its URI. Prior to this change,
  Kong 0.10 would unconditionally append a trailing slash to all upstream
  requests. The added functionality is described in
  [#2211](https://github.com/Kong/kong/issues/2211), and was implemented in
  [#2315](https://github.com/Kong/kong/pull/2315).
- Ability to hide Kong-specific response headers. Two new configuration fields:
  `server_tokens` and `latency_tokens` will respectively toggle whether the
  `Server` and `X-Kong-*-Latency` headers should be sent to downstream clients.
  [#2259](https://github.com/Kong/kong/pull/2259)
- New `cassandra_schema_consensus_timeout` configuration property, to allow for
  Kong to wait for the schema consensus of your Cassandra cluster during
  migrations.
  [#2326](https://github.com/Kong/kong/pull/2326)
- Serf commands executed by a running Kong node are now logged in the Nginx
  error logs with a `DEBUG` level.
  [#2410](https://github.com/Kong/kong/pull/2410)
- Ensure the required shared dictionaries are defined in the Nginx
  configuration. This will prevent custom Nginx templates from potentially
  resulting in a breaking upgrade for users.
  [#2466](https://github.com/Kong/kong/pull/2466)
- Admin API:
  - Target Objects can now be deleted with their ID as well as their name. The
    endpoint becomes: `/upstreams/:name_or_id/targets/:target_or_id`.
    [#2304](https://github.com/Kong/kong/pull/2304)
- Plugins:
  - :fireworks: **New Request termination plugin**. This plugin allows to
    temporarily disable an API and return a pre-configured response status and
    body to your client. Useful for use-cases such as maintenance mode for your
    upstream services. Thanks to [@pauldaustin](https://github.com/pauldaustin)
    for the contribution.
    [#2051](https://github.com/Kong/kong/pull/2051)
  - Logging plugins: The produced logs include two new fields: a `consumer`
    field, which contains the properties of the authenticated Consumer
    (`id`, `custom_id`, and `username`), if any, and a `tries` field, which
    includes the upstream connection successes and failures of the load-
    balancer.
    [#2367](https://github.com/Kong/kong/pull/2367)
    [#2429](https://github.com/Kong/kong/pull/2429)
  - http-log: Now set an upstream HTTP basic access authentication header if
    the configured `conf.http_endpoint` parameter includes an authentication
    section. Thanks [@amir](https://github.com/amir) for the contribution.
    [#2432](https://github.com/Kong/kong/pull/2432)
  - file-log: New `config.reopen` property to close and reopen the log file on
    every request, in order to effectively rotate the logs.
    [#2348](https://github.com/Kong/kong/pull/2348)
  - jwt: Returns `401 Unauthorized` on invalid claims instead of the previous
    `403 Forbidden` status.
    [#2433](https://github.com/Kong/kong/pull/2433)
  - key-auth: Allow setting API key header names with an underscore.
    [#2370](https://github.com/Kong/kong/pull/2370)
  - cors: When `config.credentials = true`, we do not send an ACAO header with
    value `*`. The ACAO header value will be that of the request's `Origin: `
    header.
    [#2451](https://github.com/Kong/kong/pull/2451)

### Fixed

- Upstream connections over TLS now set their Client Hello SNI field. The SNI
  value is taken from the upstream `Host` header value, and thus also depends
  on the `preserve_host` setting of your API. Thanks
  [@konrade](https://github.com/konrade) for the original patch.
  [#2225](https://github.com/Kong/kong/pull/2225)
- Correctly match APIs with percent-encoded URIs in their `uris` property.
  Generally, this change also avoids normalizing (and thus, potentially
  altering) the request URI when trying to match an API's `uris` value. Instead
  of relying on the Nginx `$uri` variable, we now use `$request_uri`.
  [#2377](https://github.com/Kong/kong/pull/2377)
- Handle a routing edge-case under some conditions with the `uris` matching
  rule of APIs that would falsely lead Kong into believing no API was matched
  for what would actually be a valid request.
  [#2343](https://github.com/Kong/kong/pull/2343)
- If no API was configured with a `hosts` matching rule, then the
  `preserve_host` flag would never be honored.
  [#2344](https://github.com/Kong/kong/pull/2344)
- The `X-Forwarded-For` header sent to your upstream services by Kong is not
  set from the Nginx `$proxy_add_x_forwarded_for` variable anymore. Instead,
  Kong uses the `$realip_remote_addr` variable to append the real IP address
  of a client, instead of `$remote_addr`, which can come from a previous proxy
  hop.
  [#2236](https://github.com/Kong/kong/pull/2236)
- CNAME records are now properly being cached by the DNS resolver. This results
  in a performance improvement over previous 0.10 versions.
  [#2303](https://github.com/Kong/kong/pull/2303)
- When using Cassandra, some migrations would not be performed on the same
  coordinator as the one originally chosen. The same migrations would also
  require a response from other replicas in a cluster, but were not waiting
  for a schema consensus beforehand, causing indeterministic failures in the
  migrations, especially if the cluster's inter-nodes communication is slow.
  [#2326](https://github.com/Kong/kong/pull/2326)
- The `cassandra_timeout` configuration property is now correctly taken into
  consideration by Kong.
  [#2326](https://github.com/Kong/kong/pull/2326)
- Correctly trigger plugins configured on the anonymous Consumer for anonymous
  requests (from auth plugins with the new `config.anonymous` parameter).
  [#2424](https://github.com/Kong/kong/pull/2424)
- When multiple auth plugins were configured with the recent `config.anonymous`
  parameter for "OR" authentication, such plugins would override each other's
  results and response headers, causing false negatives.
  [#2222](https://github.com/Kong/kong/pull/2222)
- Ensure the `cassandra_contact_points` property does not contain any port
  information. Those should be specified in `cassandra_port`. Thanks
  [@Vermeille](https://github.com/Vermeille) for the contribution.
  [#2263](https://github.com/Kong/kong/pull/2263)
- Prevent an upstream or legitimate internal error in the load balancing code
  from throwing a Lua-land error as well.
  [#2327](https://github.com/Kong/kong/pull/2327)
- Allow backwards compatibility with custom Nginx configurations that still
  define the `resolver ${{DNS_RESOLVER}}` directive. Vales from the Kong
  `dns_resolver` property will be flattened to a string and appended to the
  directive.
  [#2386](https://github.com/Kong/kong/pull/2386)
- Plugins:
  - hmac: Better handling of invalid base64-encoded signatures. Previously Kong
    would return an HTTP 500 error. We now properly return HTTP 403 Forbidden.
    [#2283](https://github.com/Kong/kong/pull/2283)
- Admin API:
  - Detect conflicts between SNI Objects in the `/snis` and `/certificates`
    endpoint.
    [#2285](https://github.com/Kong/kong/pull/2285)
  - The `/certificates` route used to not return the `total` and `data` JSON
    fields. We now send those fields back instead of a root list of certificate
    objects.
    [#2463](https://github.com/Kong/kong/pull/2463)
  - Endpoints with path parameters like `/xxx_or_id` will now also yield the
    proper result if the `xxx` field is formatted as a UUID. Most notably, this
    fixes a problem for Consumers whose `username` is a UUID, that could not be
    found when requesting `/consumers/{username_as_uuid}`.
    [#2420](https://github.com/Kong/kong/pull/2420)
  - The "active targets" endpoint does not require a trailing slash anymore.
    [#2307](https://github.com/Kong/kong/pull/2307)
  - Upstream Objects can now be deleted properly when using Cassandra.
    [#2404](https://github.com/Kong/kong/pull/2404)

[Back to TOC](#table-of-contents)

## [0.10.1] - 2017/03/27

### Changed

- :warning: Serf has been downgraded to version 0.7 in our distributions,
  although versions up to 0.8.1 are still supported. This fixes a problem when
  automatically detecting the first non-loopback private IP address, which was
  defaulted to `127.0.0.1` in Kong 0.10.0. Greater versions of Serf can still
  be used, but the IP address needs to be manually specified in the
  `cluster_advertise` configuration property.
- :warning: The [CORS Plugin](https://getkong.org/plugins/cors/) parameter
  `config.origin` is now `config.origins`.
  [#2203](https://github.com/Kong/kong/pull/2203)

   :red_circle: **Post-release note (as of 2017/05/12)**: A faulty behavior
   has been observed with this change. Previously, the plugin would send the
   `*` wildcard when `config.origin` was not specified. With this change, the
   plugin **does not** send the `*` wildcard by default anymore. You will need
   to specify it manually when configuring the plugin, with `config.origins=*`.
   This behavior is to be fixed in a future release.

   :white_check_mark: **Update (2017/05/24)**: A fix to this regression has been
   released as part of 0.10.3. See the section of the Changelog related to this
   release for more details.
- Admin API:
  - Disable support for TLS/1.0.
    [#2212](https://github.com/Kong/kong/pull/2212)

### Added

- Admin API:
  - Active targets can be pulled with `GET /upstreams/{name}/targets/active`.
    [#2230](https://github.com/Kong/kong/pull/2230)
  - Provide a convenience endpoint to disable targets at:
    `DELETE /upstreams/{name}/targets/{target}`.
    Under the hood, this creates a new target with `weight = 0` (the
    correct way of disabling targets, which used to cause confusion).
    [#2256](https://github.com/Kong/kong/pull/2256)
- Plugins:
  - cors: Support for configuring multiple Origin domains.
    [#2203](https://github.com/Kong/kong/pull/2203)

### Fixed

- Use an LRU cache for Lua-land entities caching to avoid exhausting the Lua
  VM memory in long-running instances.
  [#2246](https://github.com/Kong/kong/pull/2246)
- Avoid potential deadlocks upon callback errors in the caching module for
  database entities.
  [#2197](https://github.com/Kong/kong/pull/2197)
- Relax multipart MIME type parsing. A space is allowed in between values
  of the Content-Type header.
  [#2215](https://github.com/Kong/kong/pull/2215)
- Admin API:
  - Better handling of non-supported HTTP methods on endpoints of the Admin
    API. In some cases this used to throw an internal error. Calling any
    endpoint with a non-supported HTTP method now always returns `405 Method
    Not Allowed` as expected.
    [#2213](https://github.com/Kong/kong/pull/2213)
- CLI:
  - Better error handling when missing Serf executable.
    [#2218](https://github.com/Kong/kong/pull/2218)
  - Fix a bug in the `kong migrations` command that would prevent it to run
    correctly.
    [#2238](https://github.com/Kong/kong/pull/2238)
  - Trim list values specified in the configuration file.
    [#2206](https://github.com/Kong/kong/pull/2206)
  - Align the default configuration file's values to the actual, hard-coded
    default values to avoid confusion.
    [#2254](https://github.com/Kong/kong/issues/2254)
- Plugins:
  - hmac: Generate an HMAC secret value if none is provided.
    [#2158](https://github.com/Kong/kong/pull/2158)
  - oauth2: Don't try to remove credential values from request bodies if the
    MIME type is multipart, since such attempts would result in an error.
    [#2176](https://github.com/Kong/kong/pull/2176)
  - ldap: This plugin should not be applied to a single Consumer, however, this
    was not properly enforced. It is now impossible to apply this plugin to a
    single Consumer (as per all authentication plugin).
    [#2237](https://github.com/Kong/kong/pull/2237)
  - aws-lambda: Support for `us-west-2` region in schema.
    [#2257](https://github.com/Kong/kong/pull/2257)

[Back to TOC](#table-of-contents)

## [0.10.0] - 2017/03/07

Kong 0.10 is one of most significant releases to this day. It ships with
exciting new features that have been heavily requested for the last few months,
such as load balancing, Cassandra 3.0 compatibility, Websockets support,
internal DNS resolution (A and SRV records without Dnsmasq), and more flexible
matching capabilities for APIs routing.

On top of those new features, this release received a particular attention to
performance, and brings many improvements and refactors that should make it
perform significantly better than any previous version.

### Changed

- :warning: API Objects (as configured via the Admin API) do **not** support
  the `request_host` and `request_uri` fields anymore. The 0.10 migrations
  should upgrade your current API Objects, but make sure to read the new [0.10
  Proxy Guide](https://getkong.org/docs/0.10.x/proxy) to learn the new routing
  capabilities of Kong. On the good side, this means that Kong can now route
  incoming requests according to a combination of Host headers, URIs, and HTTP
  methods.
- :warning: Final slashes in `upstream_url` are no longer allowed.
  [#2115](https://github.com/Kong/kong/pull/2115)
- :warning: The SSL plugin has been removed and dynamic SSL capabilities have
  been added to Kong core, and are configurable via new properties on the API
  entity. See the related PR for a detailed explanation of this change.
  [#1970](https://github.com/Kong/kong/pull/1970)
- :warning: Drop the Dnsmasq dependency. We now internally resolve both A and
  SRV DNS records.
  [#1587](https://github.com/Kong/kong/pull/1587)
- :warning: Dropping support for insecure `TLS/1.0` and defaulting `Upgrade`
  responses to `TLS/1.2`.
  [#2119](https://github.com/Kong/kong/pull/2119)
- Bump the compatible OpenResty version to `1.11.2.1` and `1.11.2.2`. Support
  for OpenResty `1.11.2.2` requires the `--without-luajit-lua52` compilation
  flag.
- Separate Admin API and Proxy error logs. Admin API logs are now written to
  `logs/admin_access.log`.
  [#1782](https://github.com/Kong/kong/pull/1782)
- Auto-generates stronger SHA-256 with RSA encryption SSL certificates.
  [#2117](https://github.com/Kong/kong/pull/2117)

### Added

- :fireworks: Support for Cassandra 3.x.
  [#1709](https://github.com/Kong/kong/pull/1709)
- :fireworks: SRV records resolution.
  [#1587](https://github.com/Kong/kong/pull/1587)
- :fireworks: Load balancing. When an A or SRV record resolves to multiple
  entries, Kong now rotates those upstream targets with a Round-Robin
  algorithm. This is a first step towards implementing more load balancing
  algorithms.
  Another way to specify multiple upstream targets is to use the newly
  introduced `/upstreams` and `/targets` entities of the Admin API.
  [#1587](https://github.com/Kong/kong/pull/1587)
  [#1735](https://github.com/Kong/kong/pull/1735)
- :fireworks: Multiple hosts and paths per API. Kong can now route incoming
  requests to your services based on a combination of Host headers, URIs and
  HTTP methods. See the related PR for a detailed explanation of the new
  properties and capabilities of the new router.
  [#1970](https://github.com/Kong/kong/pull/1970)
- :fireworks: Maintain upstream connection pools which should greatly improve
  performance, especially for HTTPS upstream connections.  We now use HTTP/1.1
  for upstream connections as well as an nginx `upstream` block with a
  configurable`keepalive` directive, thanks to the new `nginx_keepalive`
  configuration property.
  [#1587](https://github.com/Kong/kong/pull/1587)
  [#1827](https://github.com/Kong/kong/pull/1827)
- :fireworks: Websockets support. Kong can now upgrade client connections to
  use the `ws` protocol when `Upgrade: websocket` is present.
  [#1827](https://github.com/Kong/kong/pull/1827)
- Use an in-memory caching strategy for database entities in order to reduce
  CPU load during requests proxying.
  [#1688](https://github.com/Kong/kong/pull/1688)
- Provide negative-caching for missed database entities. This should improve
  performance in some cases.
  [#1914](https://github.com/Kong/kong/pull/1914)
- Support for serving the Admin API over SSL. This introduces new properties in
  the configuration file: `admin_listen_ssl`, `admin_ssl`, `admin_ssl_cert` and
  `admin_ssl_cert_key`.
  [#1706](https://github.com/Kong/kong/pull/1706)
- Support for upstream connection timeouts. APIs now have 3 new fields:
  `upstream_connect_timeout`, `upstream_send_timeout`, `upstream_read_timeout`
  to specify, in milliseconds, a timeout value for requests between Kong and
  your APIs.
  [#2036](https://github.com/Kong/kong/pull/2036)
- Support for clustering key rotation in the underlying Serf process:
  - new `cluster_keyring_file` property in the configuration file.
  - new `kong cluster keys ..` CLI commands that expose the underlying
    `serf keys ..` commands.
  [#2069](https://github.com/Kong/kong/pull/2069)
- Support for `lua_socket_pool_size` property in configuration file.
  [#2109](https://github.com/Kong/kong/pull/2109)
- Plugins:
  - :fireworks: **New AWS Lambda plugin**. Thanks Tim Erickson for his
    collaboration on this new addition.
    [#1777](https://github.com/Kong/kong/pull/1777)
    [#1190](https://github.com/Kong/kong/pull/1190)
  - Anonymous authentication for auth plugins. When such plugins receive the
    `config.anonymous=<consumer_id>` property, even non-authenticated requests
    will be proxied by Kong, with the traditional Consumer headers set to the
    designated anonymous consumer, but also with a `X-Anonymous-Consumer`
    header. Multiple auth plugins will work in a logical `OR` fashion.
    [#1666](https://github.com/Kong/kong/pull/1666) and
    [#2035](https://github.com/Kong/kong/pull/2035)
  - request-transformer: Ability to change the HTTP method of the upstream
    request. [#1635](https://github.com/Kong/kong/pull/1635)
  - jwt: Support for ES256 signatures.
    [#1920](https://github.com/Kong/kong/pull/1920)
  - rate-limiting: Ability to select the Redis database to use via the new
    `config.redis_database` plugin property.
    [#1941](https://github.com/Kong/kong/pull/1941)

### Fixed

- Looking for Serf in known installation paths.
  [#1997](https://github.com/Kong/kong/pull/1997)
- Including port in upstream `Host` header.
  [#2045](https://github.com/Kong/kong/pull/2045)
- Clarify the purpose of the `cluster_listen_rpc` property in
  the configuration file. Thanks Jeremy Monin for the patch.
  [#1860](https://github.com/Kong/kong/pull/1860)
- Admin API:
  - Properly Return JSON responses (instead of HTML) on HTTP 409 Conflict
    when adding Plugins.
    [#2014](https://github.com/Kong/kong/issues/2014)
- CLI:
  - Avoid double-prefixing migration error messages with the database name
    (PostgreSQL/Cassandra).
- Plugins:
  - Fix fault tolerance logic and error reporting in rate-limiting plugins.
  - CORS: Properly return `Access-Control-Allow-Credentials: false` if
    `Access-Control-Allow-Origin: *`.
    [#2104](https://github.com/Kong/kong/pull/2104)
  - key-auth: enforce `key_names` to be proper header names according to Nginx.
    [#2142](https://github.com/Kong/kong/pull/2142)

[Back to TOC](#table-of-contents)

## [0.9.9] - 2017/02/02

### Fixed

- Correctly put Cassandra sockets into the Nginx connection pool for later
  reuse. This greatly improves the performance for rate-limiting and
  response-ratelimiting plugins.
  [f8f5306](https://github.com/Kong/kong/commit/f8f53061207de625a29bbe5d80f1807da468a1bc)
- Correct length of a year in seconds for rate-limiting and
  response-ratelimiting plugins. A year was wrongly assumed to only be 360
  days long.
  [e4fdb2a](https://github.com/Kong/kong/commit/e4fdb2a3af4a5f2bf298c7b6488d88e67288c98b)
- Prevent misinterpretation of the `%` character in proxied URLs encoding.
  Thanks Thomas Jouannic for the patch.
  [#1998](https://github.com/Kong/kong/pull/1998)
  [#2040](https://github.com/Kong/kong/pull/2040)

[Back to TOC](#table-of-contents)

## [0.9.8] - 2017/01/19

### Fixed

- Properly set the admin IP in the Serf script.

### Changed

- Provide negative-caching for missed database entities. This should improve
  performance in some cases.
  [#1914](https://github.com/Kong/kong/pull/1914)

### Fixed

- Plugins:
  - Fix fault tolerance logic and error reporting in rate-limiting plugins.

[Back to TOC](#table-of-contents)

## [0.9.7] - 2016/12/21

### Fixed

- Fixed a performance issue in Cassandra by removing an old workaround that was
  forcing Cassandra to use LuaSocket instead of cosockets.
  [#1916](https://github.com/Kong/kong/pull/1916)
- Fixed an issue that was causing a recursive attempt to stop Kong's services
  when an error was occurring.
  [#1877](https://github.com/Kong/kong/pull/1877)
- Custom plugins are now properly loaded again.
  [#1910](https://github.com/Kong/kong/pull/1910)
- Plugins:
  - Galileo: properly encode empty arrays.
    [#1909](https://github.com/Kong/kong/pull/1909)
  - OAuth 2: implements a missing Postgres migration for `redirect_uri` in
    every OAuth 2 credential. [#1911](https://github.com/Kong/kong/pull/1911)
  - OAuth 2: safely parse the request body even when no data has been sent.
    [#1915](https://github.com/Kong/kong/pull/1915)

[Back to TOC](#table-of-contents)

## [0.9.6] - 2016/11/29

### Fixed

- Resolve support for PostgreSQL SSL connections.
  [#1720](https://github.com/Kong/kong/issues/1720)
- Ensure `kong start` honors the `--conf` flag is a config file already exists
  at one of the default locations (`/etc/kong.conf`, `/etc/kong/kong.conf`).
  [#1681](https://github.com/Kong/kong/pull/1681)
- Obfuscate sensitive properties from the `/` Admin API route which returns
  the current node's configuration.
  [#1650](https://github.com/Kong/kong/pull/1650)

[Back to TOC](#table-of-contents)

## [0.9.5] - 2016/11/07

### Changed

- Dropping support for OpenResty 1.9.15.1 in favor of 1.11.2.1
  [#1797](https://github.com/Kong/kong/pull/1797)

### Fixed

- Fixed an error (introduced in 0.9.4) in the auto-clustering event

[Back to TOC](#table-of-contents)

## [0.9.4] - 2016/11/02

### Fixed

- Fixed the random string generator that was causing some problems, especially
  in Serf for clustering. [#1754](https://github.com/Kong/kong/pull/1754)
- Seed random number generator in CLI.
  [#1641](https://github.com/Kong/kong/pull/1641)
- Reducing log noise in the Admin API.
  [#1781](https://github.com/Kong/kong/pull/1781)
- Fixed the reports lock implementation that was generating a periodic error
  message. [#1783](https://github.com/Kong/kong/pull/1783)

[Back to TOC](#table-of-contents)

## [0.9.3] - 2016/10/07

### Added

- Added support for Serf 0.8. [#1693](https://github.com/Kong/kong/pull/1693)

### Fixed

- Properly invalidate global plugins.
  [#1723](https://github.com/Kong/kong/pull/1723)

[Back to TOC](#table-of-contents)

## [0.9.2] - 2016/09/20

### Fixed

- Correctly report migrations errors. This was caused by an error being thrown
  from the error handler, and superseding the actual error. [#1605]
  (https://github.com/Kong/kong/pull/1605)
- Prevent Kong from silently failing to start. This would be caused by an
  erroneous error handler. [28f5d10]
  (https://github.com/Kong/kong/commit/28f5d10)
- Only report a random number generator seeding error when it is not already
  seeded. [#1613](https://github.com/Kong/kong/pull/1613)
- Reduce intra-cluster noise by not propagating keepalive requests events.
  [#1660](https://github.com/Kong/kong/pull/1660)
- Admin API:
  - Obfuscates sensitive configuration settings from the `/` route.
    [#1650](https://github.com/Kong/kong/pull/1650)
- CLI:
  - Prevent a failed `kong start` to stop an already running Kong node.
    [#1645](https://github.com/Kong/kong/pull/1645)
  - Remove unset configuration placeholders from the nginx configuration
    template. This would occur when no Internet connection would be
    available and would cause Kong to compile an erroneous nginx config.
    [#1606](https://github.com/Kong/kong/pull/1606)
  - Properly count the number of executed migrations.
    [#1649](https://github.com/Kong/kong/pull/1649)
- Plugins:
  - OAuth2: remove the "Kong" mentions in missing `provision_key` error
    messages. [#1633](https://github.com/Kong/kong/pull/1633)
  - OAuth2: allow to correctly delete applications when using Cassandra.
    [#1659](https://github.com/Kong/kong/pull/1659)
  - galileo: provide a default `bodySize` value when `log_bodies=true` but the
    current request/response has no body.
    [#1657](https://github.com/Kong/kong/pull/1657)

[Back to TOC](#table-of-contents)

## [0.9.1] - 2016/09/02

### Added

- Plugins:
  - ACL: allow to retrieve/update/delete an ACL by group name.
    [#1544](https://github.com/Kong/kong/pull/1544)
  - Basic Authentication: allow to retrieve/update/delete a credential by `username`.
    [#1570](https://github.com/Kong/kong/pull/1570)
  - HMAC Authentication: allow to retrieve/update/delete a credential by `username`.
    [#1570](https://github.com/Kong/kong/pull/1570)
  - JWT Authentication: allow to retrieve/update/delete a credential by `key`.
    [#1570](https://github.com/Kong/kong/pull/1570)
  - Key Authentication: allow to retrieve/update/delete a credential by `key`.
    [#1570](https://github.com/Kong/kong/pull/1570)
  - OAuth2 Authentication: allow to retrieve/update/delete a credential by `client_id` and tokens by `access_token`.
    [#1570](https://github.com/Kong/kong/pull/1570)

### Fixed

- Correctly parse configuration file settings containing comments.
  [#1569](https://github.com/Kong/kong/pull/1569)
- Prevent third-party Lua modules (and plugins) to override the seed for random
  number generation. This prevents the creation of conflicting UUIDs.
  [#1558](https://github.com/Kong/kong/pull/1558)
- Use [pgmoon-mashape](https://github.com/Kong/pgmoon) `2.0.0` which
  properly namespaces our fork, avoiding conflicts with other versions of
  pgmoon, such as the one installed by Lapis.
  [#1582](https://github.com/Kong/kong/pull/1582)
- Avoid exposing OpenResty's information on HTTP `4xx` errors.
  [#1567](https://github.com/Kong/kong/pull/1567)
- ulimit with `unlimited` value is now properly handled.
  [#1545](https://github.com/Kong/kong/pull/1545)
- CLI:
  - Stop third-party services (Dnsmasq/Serf) when Kong could not start.
    [#1588](https://github.com/Kong/kong/pull/1588)
  - Prefix database migration errors (such as Postgres' `connection refused`)
    with the database name (`postgres`/`cassandra`) to avoid confusions.
    [#1583](https://github.com/Kong/kong/pull/1583)
- Plugins:
  - galileo: Use `Content-Length` header to get request/response body size when
    `log_bodies` is disabled.
    [#1584](https://github.com/Kong/kong/pull/1584)
- Admin API:
  - Revert the `/plugins/enabled` endpoint's response to be a JSON array, and
    not an Object. [#1529](https://github.com/Kong/kong/pull/1529)

[Back to TOC](#table-of-contents)

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
- :fireworks: Support for SSL connections between Kong and PostgreSQL. [#1425](https://github.com/Kong/kong/pull/1425)
- :fireworks: Ability to apply plugins with more granularity: per-consumer, and global plugins are now possible. [#1403](https://github.com/Kong/kong/pull/1403)
- New `kong check` command: validates a Kong configuration file.
- Better version check for third-party dependencies (OpenResty, Serf, Dnsmasq). [#1307](https://github.com/Kong/kong/pull/1307)
- Ability to configure the validation depth of database SSL certificates from the configuration file. [#1420](https://github.com/Kong/kong/pull/1420)
- `request_host`: internationalized url support; utf-8 domain names through punycode support and paths through %-encoding. [#1300](https://github.com/Kong/kong/issues/1300)
- Implements caching locks when fetching database configuration (APIs, Plugins...) to avoid dog pile effect on cold nodes. [#1402](https://github.com/Kong/kong/pull/1402)
- Plugins:
  - :fireworks: **New bot-detection plugin**: protect your APIs by detecting and rejecting common bots and crawlers. [#1413](https://github.com/Kong/kong/pull/1413)
  - correlation-id: new "tracker" generator, identifying requests per worker and connection. [#1288](https://github.com/Kong/kong/pull/1288)
  - request/response-transformer: ability to add strings including colon characters. [#1353](https://github.com/Kong/kong/pull/1353)
  - rate-limiting: support for new rate-limiting policies (`cluster`, `local` and `redis`), and for a new `limit_by` property to force rate-limiting by `consumer`, `credential` or `ip`.
  - response-rate-limiting: support for new rate-limiting policies (`cluster`, `local` and `redis`), and for a new `limit_by` property to force rate-limiting by `consumer`, `credential` or `ip`.
  - galileo: performance improvements of ALF serialization. ALFs are not discarded when exceeding 20MBs anymore. [#1463](https://github.com/Kong/kong/issues/1463)
  - statsd: new `upstream_stream` latency metric. [#1466](https://github.com/Kong/kong/pull/1466)
  - datadog: new `upstream_stream` latency metric and tagging support for each metric. [#1473](https://github.com/Kong/kong/pull/1473)

### Removed

- We now use [lua-resty-jit-uuid](https://github.com/thibaultCha/lua-resty-jit-uuid) for UUID generation, which is a pure Lua implementation of [RFC 4122](https://www.ietf.org/rfc/rfc4122.txt). As a result, libuuid is not a dependency of Kong anymore.

### Fixed

- Sensitive configuration settings are not printed to stdout anymore. [#1256](https://github.com/Kong/kong/issues/1256)
- Fixed bug that caused nodes to remove themselves from the database when they attempted to join the cluster. [#1437](https://github.com/Kong/kong/pull/1437)
- Plugins:
  - request-size-limiting: use proper constant for MB units while setting the size limit. [#1416](https://github.com/Kong/kong/pull/1416)
  - OAuth2: security and config validation fixes. [#1409](https://github.com/Kong/kong/pull/1409) [#1112](https://github.com/Kong/kong/pull/1112)
  - request/response-transformer: better validation of fields provided without a value. [#1399](https://github.com/Kong/kong/pull/1399)
  - JWT: handle some edge-cases that could result in HTTP 500 errors. [#1362](https://github.com/Kong/kong/pull/1362)

> **internal**
> - new test suite using resty-cli and removing the need to monkey-patch the `ngx` global.
> - custom assertions and new helper methods (`wait_until()`) to gracefully fail in case of timeout.
> - increase atomicity of the testing environment.
> - lighter testing instance, only running 1 worker and not using Dnsmasq by default.

[Back to TOC](#table-of-contents)

## [0.8.3] - 2016/06/01

This release includes some bugfixes:

### Changed

- Switched the log level of the "No nodes found in cluster" warning to `INFO`, that was printed when starting up the first Kong node in a new cluster.
- Kong now requires OpenResty `1.9.7.5`.

### Fixed

- New nodes are now properly registered into the `nodes` table when running on the same machine. [#1281](https://github.com/Kong/kong/pull/1281)
- Fixed a failed error parsing on Postgres. [#1269](https://github.com/Kong/kong/pull/1269)
- Plugins:
  - Response Transformer: Slashes are now encoded properly, and fixed a bug that hang the execution of the plugin. [#1257](https://github.com/Kong/kong/pull/1257) and [#1263](https://github.com/Kong/kong/pull/1263)
  - JWT: If a value for `algorithm` is missing, it's now `HS256` by default. This problem occurred when migrating from older versions of Kong.
  - OAuth 2.0: Fixed a Postgres problem that was preventing an application from being created, and fixed a check on the `redirect_uri` field. [#1264](https://github.com/Kong/kong/pull/1264) and [#1267](https://github.com/Kong/kong/issues/1267)

[Back to TOC](#table-of-contents)

## [0.8.2] - 2016/05/25

This release includes bugfixes and minor updates:

### Added

- Support for a simple slash in `request_path`. [#1227](https://github.com/Kong/kong/pull/1227)
- Plugins:
  - Response Rate Limiting: it now appends usage headers to the upstream requests in the form of `X-Ratelimit-Remaining-{limit_name}` and introduces a new `config.block_on_first_violation` property. [#1235](https://github.com/Kong/kong/pull/1235)

#### Changed

- Plugins:
  - **Mashape Analytics: The plugin is now called "Galileo", and added support for Galileo v3. [#1159](https://github.com/Kong/kong/pull/1159)**

#### Fixed

- Postgres now relies on the `search_path` configured on the database and its default value `$user, public`. [#1196](https://github.com/Kong/kong/issues/1196)
- Kong now properly encodes an empty querystring parameter like `?param=` when proxying the request. [#1210](https://github.com/Kong/kong/pull/1210)
- The configuration now checks that `cluster.ttl_on_failure` is at least 60 seconds. [#1199](https://github.com/Kong/kong/pull/1199)
- Plugins:
  - Loggly: Fixed an issue that was triggering 400 and 500 errors. [#1184](https://github.com/Kong/kong/pull/1184)
  - JWT: The `TYP` value in the header is not optional and case-insensitive. [#1192](https://github.com/Kong/kong/pull/1192)
  - Request Transformer: Fixed a bug when transforming request headers. [#1202](https://github.com/Kong/kong/pull/1202)
  - OAuth 2.0: Multiple redirect URIs are now supported. [#1112](https://github.com/Kong/kong/pull/1112)
  - IP Restriction: Fixed that prevented the plugin for working properly when added on an API. [#1245](https://github.com/Kong/kong/pull/1245)
  - CORS: Fixed an issue when `config.preflight_continue` was enabled. [#1240](https://github.com/Kong/kong/pull/1240)

[Back to TOC](#table-of-contents)

## [0.8.1] - 2016/04/27

This release includes some fixes and minor updates:

### Added

- Adds `X-Forwarded-Host` and `X-Forwarded-Prefix` to the upstream request headers. [#1180](https://github.com/Kong/kong/pull/1180)
- Plugins:
  - Datadog: Added two new metrics, `unique_users` and `request_per_user`, that log the consumer information. [#1179](https://github.com/Kong/kong/pull/1179)

### Fixed

- Fixed a DAO bug that affected full entity updates. [#1163](https://github.com/Kong/kong/pull/1163)
- Fixed a bug when setting the authentication provider in Cassandra.
- Updated the Cassandra driver to v0.5.2.
- Properly enforcing required fields in PUT requests. [#1177](https://github.com/Kong/kong/pull/1177)
- Fixed a bug that prevented to retrieve the hostname of the local machine on certain systems. [#1178](https://github.com/Kong/kong/pull/1178)

[Back to TOC](#table-of-contents)

## [0.8.0] - 2016/04/18

This release includes support for PostgreSQL as Kong's primary datastore!

### Breaking changes

- Remove support for the long deprecated `/consumers/:consumer/keyauth/` and `/consumers/:consumer/basicauth/` routes (deprecated in `0.5.0`). The new routes (available since `0.5.0` too) use the real name of the plugin: `/consumers/:consumer/key-auth` and `/consumers/:consumer/basic-auth`.

### Added

- Support for PostgreSQL 9.4+ as Kong's primary datastore. [#331](https://github.com/Kong/kong/issues/331) [#1054](https://github.com/Kong/kong/issues/1054)
- Configurable Cassandra reading/writing consistency. [#1026](https://github.com/Kong/kong/pull/1026)
- Admin API: including pending and running timers count in the response to `/`. [#992](https://github.com/Kong/kong/pull/992)
- Plugins
  - **New correlation-id plugin**: assign unique identifiers to the requests processed by Kong. Courtesy of [@opyate](https://github.com/opyate). [#1094](https://github.com/Kong/kong/pull/1094)
  - LDAP: add support for LDAP authentication. [#1133](https://github.com/Kong/kong/pull/1133)
  - StatsD: add support for StatsD logging. [#1142](https://github.com/Kong/kong/pull/1142)
  - JWT: add support for RS256 signed tokens thanks to [@kdstew](https://github.com/kdstew)! [#1053](https://github.com/Kong/kong/pull/1053)
  - ACL: appends `X-Consumer-Groups` to the request, so the upstream service can check what groups the consumer belongs to. [#1154](https://github.com/Kong/kong/pull/1154)
  - Galileo (mashape-analytics): increase batch sending timeout to 30s. [#1091](https://github.com/Kong/kong/pull/1091)
- Added `ttl_on_failure` option in the cluster configuration, to configure the TTL of failed nodes. [#1125](https://github.com/Kong/kong/pull/1125)

### Fixed

- Introduce a new `port` option when connecting to your Cassandra cluster instead of using the CQL default (9042). [#1139](https://github.com/Kong/kong/issues/1139)
- Plugins
  - Request/Response Transformer: add missing migrations for upgrades from ` <= 0.5.x`. [#1064](https://github.com/Kong/kong/issues/1064)
  - OAuth2
    - Error responses comply to RFC 6749. [#1017](https://github.com/Kong/kong/issues/1017)
    - Handle multipart requests. [#1067](https://github.com/Kong/kong/issues/1067)
    - Make access_tokens correctly expire. [#1089](https://github.com/Kong/kong/issues/1089)

> **internal**
> - replace globals with singleton pattern thanks to [@mars](https://github.com/mars).
> - fixed resolution mismatches when using deep paths in the path resolver.

[Back to TOC](#table-of-contents)

## [0.7.0] - 2016/02/24

### Breaking changes

Due to the NGINX security fixes (CVE-2016-0742, CVE-2016-0746, CVE-2016-0747), OpenResty was bumped to `1.9.7.3` which is not backwards compatible, and thus requires changes to be made to the `nginx` property of Kong's configuration file. See the [0.7 upgrade path](https://github.com/Kong/kong/blob/master/UPGRADE.md#upgrade-to-07x) for instructions.

However by upgrading the underlying OpenResty version, source installations do not have to patch the NGINX core and use the old `ssl-cert-by-lua` branch of ngx_lua anymore. This will make source installations much easier.

### Added

- Support for OpenResty `1.9.7.*`. This includes NGINX security fixes (CVE-2016-0742, CVE-2016-0746, CVE-2016-0747). [#906](https://github.com/Kong/kong/pull/906)
- Plugins
  - **New Runscope plugin**: Monitor your APIs from Kong with Runscope. Courtesy of [@mansilladev](https://github.com/mansilladev). [#924](https://github.com/Kong/kong/pull/924)
  - Datadog: New `response.size` metric. [#923](https://github.com/Kong/kong/pull/923)
  - Rate-Limiting and Response Rate-Limiting
    - New `config.async` option to asynchronously increment counters to reduce latency at the cost of slightly reducing the accuracy. [#912](https://github.com/Kong/kong/pull/912)
    - New `config.continue_on_error` option to keep proxying requests in case the datastore is unreachable. rate-limiting operations will be disabled until the datastore is responsive again. [#953](https://github.com/Kong/kong/pull/953)
- CLI
  - Perform a simple permission check on the NGINX working directory when starting, to prevent errors during execution. [#939](https://github.com/Kong/kong/pull/939)
- Send 50x errors with the appropriate format. [#927](https://github.com/Kong/kong/pull/927) [#970](https://github.com/Kong/kong/pull/970)

### Fixed

- Plugins
  - OAuth2
    - Better handling of `redirect_uri` (prevent the use of fragments and correctly handle querystrings). Courtesy of [@PGBI](https://github.com/PGBI). [#930](https://github.com/Kong/kong/pull/930)
    - Add `PUT` support to the `/auth2_tokens` route. [#897](https://github.com/Kong/kong/pull/897)
    - Better error message when the `access_token` is missing. [#1003](https://github.com/Kong/kong/pull/1003)
  - IP restriction: Fix an issue that could arise when restarting Kong. Now Kong does not need to be restarted for the ip-restriction configuration to take effect. [#782](https://github.com/Kong/kong/pull/782) [#960](https://github.com/Kong/kong/pull/960)
  - ACL: Properly invalidating entities when assigning a new ACL group. [#996](https://github.com/Kong/kong/pull/996)
  - SSL: Replace shelled out openssl calls with native `ngx.ssl` conversion utilities, which preserve the certificate chain. [#968](https://github.com/Kong/kong/pull/968)
- Avoid user warning on start when the user is not root. [#964](https://github.com/Kong/kong/pull/964)
- Store Serf logs in NGINX working directory to prevent eventual permission issues. [#975](https://github.com/Kong/kong/pull/975)
- Allow plugins configured on a Consumer *without* being configured on an API to run. [#978](https://github.com/Kong/kong/issues/978) [#980](https://github.com/Kong/kong/pull/980)
- Fixed an edge-case where Kong nodes would not be registered in the `nodes` table. [#1008](https://github.com/Kong/kong/pull/1008)

[Back to TOC](#table-of-contents)

## [0.6.1] - 2016/02/03

This release contains tiny bug fixes that were especially annoying for complex Cassandra setups and power users of the Admin API!

### Added

- A `timeout` property for the Cassandra configuration. In ms, this timeout is effective as a connection and a reading timeout. [#937](https://github.com/Kong/kong/pull/937)

### Fixed

- Correctly set the Cassandra SSL certificate in the Nginx configuration while starting Kong. [#921](https://github.com/Kong/kong/pull/921)
- Rename the `user` Cassandra property to `username` (Kong looks for `username`, hence `user` would fail). [#922](https://github.com/Kong/kong/pull/922)
- Allow Cassandra authentication with arbitrary plain text auth providers (such as Instaclustr uses), fixing authentication with them. [#937](https://github.com/Kong/kong/pull/937)
- Admin API
  - Fix the `/plugins/:id` route for `PATCH` method. [#941](https://github.com/Kong/kong/pull/941)
- Plugins
  - HTTP logging: remove the additional `\r\n` at the end of the logging request body. [#926](https://github.com/Kong/kong/pull/926)
  - Galileo: catch occasional internal errors happening when a request was cancelled by the client and fix missing shm for the retry policy. [#931](https://github.com/Kong/kong/pull/931)

[Back to TOC](#table-of-contents)

## [0.6.0] - 2016/01/22

### Breaking changes

 We would recommended to consult the suggested [0.6 upgrade path](https://github.com/Kong/kong/blob/master/UPGRADE.md#upgrade-to-06x) for this release.

- [Serf](https://www.serf.io/) is now a Kong dependency. It allows Kong nodes to communicate between each other opening the way to many features and improvements.
- The configuration file changed. Some properties were renamed, others were moved, and some are new. We would recommend checking out the new default configuration file.
- Drop the Lua 5.1 dependency which was only used by the CLI. The CLI now runs with LuaJIT, which is consistent with other Kong components (Luarocks and OpenResty) already relying on LuaJIT. Make sure the LuaJIT interpreter is included in your `$PATH`. [#799](https://github.com/Kong/kong/pull/799)

### Added

One of the biggest new features of this release is the cluster-awareness added to Kong in [#729](https://github.com/Kong/kong/pull/729), which deserves its own section:

- Each Kong node is now aware of belonging to a cluster through Serf. Nodes automatically join the specified cluster according to the configuration file's settings.
- The datastore cache is not invalidated by expiration time anymore, but following an invalidation strategy between the nodes of a same cluster, leading to improved performance.
- Admin API
  - Expose a `/cache` endpoint for retrieving elements stored in the in-memory cache of a node.
  - Expose a `/cluster` endpoint used to add/remove/list members of the cluster, and also used internally for data propagation.
- CLI
  - New `kong cluster` command for cluster management.
  - New `kong status` command for cluster healthcheck.

Other additions include:

- New Cassandra driver which makes Kong aware of the Cassandra cluster. Kong is now unaffected if one of your Cassandra nodes goes down as long as a replica is available on another node. Load balancing policies also improve the performance along with many other smaller improvements. [#803](https://github.com/Kong/kong/pull/803)
- Admin API
  - A new `total` field in API responses, that counts the total number of entities in the datastore. [#635](https://github.com/Kong/kong/pull/635)
- Configuration
  - Possibility to configure the keyspace replication strategy for Cassandra. It will be taken into account by the migrations when the configured keyspace does not already exist. [#350](https://github.com/Kong/kong/issues/350)
  - Dnsmasq is now optional. You can specify a custom DNS resolver address that Kong will use when resolving hostnames. This can be configured in `kong.yml`. [#625](https://github.com/Kong/kong/pull/625)
- Plugins
  - **New "syslog" plugin**: send logs to local system log. [#698](https://github.com/Kong/kong/pull/698)
  - **New "loggly" plugin**: send logs to Loggly over UDP. [#698](https://github.com/Kong/kong/pull/698)
  - **New "datadog" plugin**: send logs to Datadog server. [#758](https://github.com/Kong/kong/pull/758)
  - OAuth2
    - Add support for `X-Forwarded-Proto` header. [#650](https://github.com/Kong/kong/pull/650)
    - Expose a new `/oauth2_tokens` endpoint with the possibility to retrieve, update or delete OAuth 2.0 access tokens. [#729](https://github.com/Kong/kong/pull/729)
  - JWT
    - Support for base64 encoded secrets. [#838](https://github.com/Kong/kong/pull/838) [#577](https://github.com/Kong/kong/issues/577)
    - Support to configure the claim in which the key is given into the token (not `iss` only anymore). [#838](https://github.com/Kong/kong/pull/838)
  - Request transformer
    - Support for more transformation options: `remove`, `replace`, `add`, `append` motivated by [#393](https://github.com/Kong/kong/pull/393). See [#824](https://github.com/Kong/kong/pull/824)
    - Support JSON body transformation. [#569](https://github.com/Kong/kong/issues/569)
  - Response transformer
    - Support for more transformation options: `remove`, `replace`, `add`, `append` motivated by [#393](https://github.com/Kong/kong/pull/393). See [#822](https://github.com/Kong/kong/pull/822)

### Changed

- As mentioned in the breaking changes section, a new configuration file format and validation. All properties are now documented and commented out with their default values. This allows for a lighter configuration file and more clarity as to what properties relate to. It also catches configuration mistakes. [#633](https://github.com/Kong/kong/pull/633)
- Replace the UUID generator library with a new implementation wrapping lib-uuid, fixing eventual conflicts happening in cases such as described in [#659](https://github.com/Kong/kong/pull/659). See [#695](https://github.com/Kong/kong/pull/695)
- Admin API
  - Increase the maximum body size to 10MB in order to handle configuration requests with heavy payloads. [#700](https://github.com/Kong/kong/pull/700)
  - Disable access logs for the `/status` endpoint.
  - The `/status` endpoint now includes `database` statistics, while the previous stats have been moved to a `server` response field. [#635](https://github.com/Kong/kong/pull/635)

### Fixed

- Behaviors described in [#603](https://github.com/Kong/kong/issues/603) related to the failure of Cassandra nodes thanks to the new driver. [#803](https://github.com/Kong/kong/issues/803)
- Latency headers are now properly included in responses sent to the client. [#708](https://github.com/Kong/kong/pull/708)
- `strip_request_path` does not add a trailing slash to the API's `upstream_url` anymore before proxying. [#675](https://github.com/Kong/kong/issues/675)
- Do not URL decode querystring before proxying the request to the upstream service. [#749](https://github.com/Kong/kong/issues/749)
- Handle cases when the request would be terminated prior to the Kong execution (that is, before ngx_lua reaches the `access_by_lua` context) in cases such as the use of a custom nginx module. [#594](https://github.com/Kong/kong/issues/594)
- Admin API
  - The PUT method now correctly updates boolean fields (such as `strip_request_path`). [#765](https://github.com/Kong/kong/pull/765)
  - The PUT method now correctly resets a plugin configuration. [#720](https://github.com/Kong/kong/pull/720)
  - PATCH correctly set previously unset fields. [#861](https://github.com/Kong/kong/pull/861)
  - In the responses, the `next` link is not being displayed anymore if there are no more entities to be returned. [#635](https://github.com/Kong/kong/pull/635)
  - Prevent the update of `created_at` fields. [#820](https://github.com/Kong/kong/pull/820)
  - Better `request_path` validation for APIs. "/" is not considered a valid path anymore. [#881](https://github.com/Kong/kong/pull/881)
- Plugins
  - Galileo: ensure the `mimeType` value is always a string in ALFs. [#584](https://github.com/Kong/kong/issues/584)
  - JWT: allow to update JWT credentials using the PATCH method. It previously used to reply with `405 Method not allowed` because the PATCH method was not implemented. [#667](https://github.com/Kong/kong/pull/667)
  - Rate limiting: fix a warning when many periods are configured. [#681](https://github.com/Kong/kong/issues/681)
  - Basic Authentication: do not re-hash the password field when updating a credential. [#726](https://github.com/Kong/kong/issues/726)
  - File log: better permissions for on file creation for file-log plugin. [#877](https://github.com/Kong/kong/pull/877)
  - OAuth2
    - Implement correct responses when the OAuth2 challenges are refused. [#737](https://github.com/Kong/kong/issues/737)
    - Handle querystring on `/authorize` and `/token` URLs. [#687](https://github.com/Kong/kong/pull/667)
    - Handle punctuation in scopes on `/authorize` and `/token` endpoints. [#658](https://github.com/Kong/kong/issues/658)

> ***internal***
> - Event bus for local and cluster-wide events propagation. Plans for this event bus is to be widely used among Kong in the future.
> - The Kong Public Lua API (Lua helpers integrated in Kong such as DAO and Admin API helpers) is now documented with [ldoc](http://stevedonovan.github.io/ldoc/).
> - Work has been done to restore the reliability of the CI platforms.
> - Migrations can now execute DML queries (instead of DDL queries only). Handy for migrations implying plugin configuration changes, plugins renamings etc... [#770](https://github.com/Kong/kong/pull/770)

[Back to TOC](#table-of-contents)

## [0.5.4] - 2015/12/03

### Fixed

- Mashape Analytics plugin (renamed Galileo):
  - Improve stability under heavy load. [#757](https://github.com/Kong/kong/issues/757)
  - base64 encode ALF request/response bodies, enabling proper support for Galileo bodies inspection capabilities. [#747](https://github.com/Kong/kong/pull/747)
  - Do not include JSON bodies in ALF `postData.params` field. [#766](https://github.com/Kong/kong/pull/766)

[Back to TOC](#table-of-contents)

## [0.5.3] - 2015/11/16

### Fixed

- Avoids additional URL encoding when proxying to an upstream service. [#691](https://github.com/Kong/kong/pull/691)
- Potential timing comparison bug in HMAC plugin. [#704](https://github.com/Kong/kong/pull/704)

### Added

- The Galileo plugin now supports arbitrary host, port and path values. [#721](https://github.com/Kong/kong/pull/721)

[Back to TOC](#table-of-contents)

## [0.5.2] - 2015/10/21

A few fixes requested by the community!

### Fixed

- Kong properly search the `nginx` in your $PATH variable.
- Plugins:
  - OAuth2: can detect that the originating protocol for a request was HTTPS through the `X-Forwarded-Proto` header and work behind another reverse proxy (load balancer). [#650](https://github.com/Kong/kong/pull/650)
  - HMAC signature: support for `X-Date` header to sign the request for usage in browsers (since the `Date` header is protected). [#641](https://github.com/Kong/kong/issues/641)

[Back to TOC](#table-of-contents)

## [0.5.1] - 2015/10/13

Fixing a few glitches we let out with 0.5.0!

### Added

- Basic Authentication and HMAC Authentication plugins now also send the `X-Credential-Username` to the upstream server.
- Admin API now accept JSON when receiving a CORS request. [#580](https://github.com/Kong/kong/pull/580)
- Add a `WWW-Authenticate` header for HTTP 401 responses for basic-auth and key-auth. [#588](https://github.com/Kong/kong/pull/588)

### Changed

- Protect Kong from POODLE SSL attacks by omitting SSLv3 (CVE-2014-3566). [#563](https://github.com/Kong/kong/pull/563)
- Remove support for key-auth key in body. [#566](https://github.com/Kong/kong/pull/566)

### Fixed

- Plugins
  - HMAC
    - The migration for this plugin is now correctly being run. [#611](https://github.com/Kong/kong/pull/611)
    - Wrong username doesn't return HTTP 500 anymore, but 403. [#602](https://github.com/Kong/kong/pull/602)
  - JWT: `iss` not being found doesn't return HTTP 500 anymore, but 403. [#578](https://github.com/Kong/kong/pull/578)
  - OAuth2: client credentials flow does not include a refresh token anymore. [#562](https://github.com/Kong/kong/issues/562)
- Fix an occasional error when updating a plugin without a config. [#571](https://github.com/Kong/kong/pull/571)

[Back to TOC](#table-of-contents)

## [0.5.0] - 2015/09/25

With new plugins, many improvements and bug fixes, this release comes with breaking changes that will require your attention.

### Breaking changes

Several breaking changes are introduced. You will have to slightly change your configuration file and a migration script will take care of updating your database cluster. **Please follow the instructions in [UPGRADE.md](/UPGRADE.md#update-to-kong-050) for an update without downtime.**
- Many plugins were renamed due to new naming conventions for consistency. [#480](https://github.com/Kong/kong/issues/480)
- In the configuration file, the Cassandra `hosts` property was renamed to `contact_points`. [#513](https://github.com/Kong/kong/issues/513)
- Properties belonging to APIs entities have been renamed for clarity. [#513](https://github.com/Kong/kong/issues/513)
  - `public_dns` -> `request_host`
  - `path` -> `request_path`
  - `strip_path` -> `strip_request_path`
  - `target_url` -> `upstream_url`
- `plugins_configurations` have been renamed to `plugins`, and their `value` property has been renamed to `config` to avoid confusions. [#513](https://github.com/Kong/kong/issues/513)
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
  - **New Response Rate Limiting plugin**: Give a usage quota to your users based on a parameter in your response. [#247](https://github.com/Kong/kong/pull/247)
  - **New ACL (Access Control) plugin**: Configure authorizations for your Consumers. [#225](https://github.com/Kong/kong/issues/225)
  - **New JWT (JSON Web Token) plugin**: Verify and authenticate JWTs. [#519](https://github.com/Kong/kong/issues/519)
  - **New HMAC signature plugin**: Verify and authenticate HMAC signed HTTP requests. [#549](https://github.com/Kong/kong/pull/549)
  - Plugins migrations. Each plugin can now have its own migration scripts if it needs to store data in your cluster. This is a step forward to improve Kong's pluggable architecture. [#443](https://github.com/Kong/kong/pull/443)
  - Basic Authentication: the password field is now sha1 encrypted. [#33](https://github.com/Kong/kong/issues/33)
  - Basic Authentication: now supports credentials in the `Proxy-Authorization` header. [#460](https://github.com/Kong/kong/issues/460)

#### Changed

- Basic Authentication and Key Authentication now require authentication parameters even when the `Expect: 100-continue` header is being sent. [#408](https://github.com/Kong/kong/issues/408)
- Key Auth plugin does not support passing the key in the request payload anymore. [#566](https://github.com/Kong/kong/pull/566)
- APIs' names cannot contain characters from the RFC 3986 reserved list. [#589](https://github.com/Kong/kong/pull/589)

#### Fixed

- Resolver
  - Making a request with a querystring will now correctly match an API's path. [#496](https://github.com/Kong/kong/pull/496)
- Admin API
  - Data associated to a given API/Consumer will correctly be deleted if related Consumer/API is deleted. [#107](https://github.com/Kong/kong/issues/107) [#438](https://github.com/Kong/kong/issues/438) [#504](https://github.com/Kong/kong/issues/504)
  - The `/api/{api_name_or_id}/plugins/{plugin_name_or_id}` changed to `/api/{api_name_or_id}/plugins/{plugin_id}` to avoid requesting the wrong plugin if two are configured for one API. [#482](https://github.com/Kong/kong/pull/482)
  - APIs created without a `name` but with a `request_path` will now have a name which defaults to the set `request_path`. [#547](https://github.com/Kong/kong/issues/547)
- Plugins
  - Mashape Analytics: More robust buffer and better error logging. [#471](https://github.com/Kong/kong/pull/471)
  - Mashape Analytics: Several ALF (API Log Format) serialization fixes. [#515](https://github.com/Kong/kong/pull/515)
  - Oauth2: A response is now returned on `http://kong:8001/consumers/{consumer}/oauth2/{oauth2_id}`. [#469](https://github.com/Kong/kong/issues/469)
  - Oauth2: Saving `authenticated_userid` on Password Grant. [#476](https://github.com/Kong/kong/pull/476)
  - Oauth2: Proper handling of the `/oauth2/authorize` and `/oauth2/token` endpoints in the OAuth 2.0 Plugin when an API with a `path` is being consumed using the `public_dns` instead. [#503](https://github.com/Kong/kong/issues/503)
  - OAuth2: Properly returning `X-Authenticated-UserId` in the `client_credentials` and `password` flows. [#535](https://github.com/Kong/kong/issues/535)
  - Response-Transformer: Properly handling JSON responses that have a charset specified in their `Content-Type` header.

[Back to TOC](#table-of-contents)

## [0.4.2] - 2015/08/10

#### Added

- Cassandra authentication and SSL encryption. [#405](https://github.com/Kong/kong/pull/405)
- `preserve_host` flag on APIs to preserve the Host header when a request is proxied. [#444](https://github.com/Kong/kong/issues/444)
- Added the Resource Owner Password Credentials Grant to the OAuth 2.0 Plugin. [#448](https://github.com/Kong/kong/issues/448)
- Auto-generation of default SSL certificate. [#453](https://github.com/Kong/kong/issues/453)

#### Changed

- Remove `cassandra.port` property in configuration. Ports are specified by having `cassandra.hosts` addresses using the `host:port` notation (RFC 3986). [#457](https://github.com/Kong/kong/pull/457)
- Default SSL certificate is now auto-generated and stored in the `nginx_working_dir`.
- OAuth 2.0 plugin now properly forces HTTPS.

#### Fixed

- Better handling of multi-nodes Cassandra clusters. [#450](https://github.com/Kong/kong/pull/405)
- mashape-analytics plugin: handling of numerical values in querystrings. [#449](https://github.com/Kong/kong/pull/405)
- Path resolver `strip_path` option wrongfully matching the `path` property multiple times in the request URI. [#442](https://github.com/Kong/kong/issues/442)
- File Log Plugin bug that prevented the file creation in some environments. [#461](https://github.com/Kong/kong/issues/461)
- Clean output of the Kong CLI. [#235](https://github.com/Kong/kong/issues/235)

[Back to TOC](#table-of-contents)

## [0.4.1] - 2015/07/23

#### Fixed

- Issues with the Mashape Analytics plugin. [#425](https://github.com/Kong/kong/pull/425)
- Handle hyphens when executing path routing with `strip_path` option enabled. [#431](https://github.com/Kong/kong/pull/431)
- Adding the Client Credentials OAuth 2.0 flow. [#430](https://github.com/Kong/kong/issues/430)
- A bug that prevented "dnsmasq" from being started on some systems, including Debian. [f7da790](https://github.com/Kong/kong/commit/f7da79057ce29c7d1f6d90f4bc160cc3d9c8611f)
- File Log plugin: optimizations by avoiding the buffered I/O layer. [20bb478](https://github.com/Kong/kong/commit/20bb478952846faefec6091905bd852db24a0289)

[Back to TOC](#table-of-contents)

## [0.4.0] - 2015/07/15

#### Added

- Implement wildcard subdomains for APIs' `public_dns`. [#381](https://github.com/Kong/kong/pull/381) [#297](https://github.com/Kong/kong/pull/297)
- Plugins
  - **New OAuth 2.0 plugin.** [#341](https://github.com/Kong/kong/pull/341) [#169](https://github.com/Kong/kong/pull/169)
  - **New Mashape Analytics plugin.** [#360](https://github.com/Kong/kong/pull/360) [#272](https://github.com/Kong/kong/pull/272)
  - **New IP whitelisting/blacklisting plugin.** [#379](https://github.com/Kong/kong/pull/379)
  - Ratelimiting: support for multiple limits. [#382](https://github.com/Kong/kong/pull/382) [#205](https://github.com/Kong/kong/pull/205)
  - HTTP logging: support for HTTPS endpoint. [#342](https://github.com/Kong/kong/issues/342)
  - Logging plugins: new properties for logs timing. [#351](https://github.com/Kong/kong/issues/351)
  - Key authentication: now auto-generates a key if none is specified. [#48](https://github.com/Kong/kong/pull/48)
- Resolver
  - `path` property now accepts arbitrary depth. [#310](https://github.com/Kong/kong/issues/310)
- Admin API
  - Enable CORS by default. [#371](https://github.com/Kong/kong/pull/371)
  - Expose a new endpoint to get a plugin configuration's schema. [#376](https://github.com/Kong/kong/pull/376) [#309](https://github.com/Kong/kong/pull/309)
  - Expose a new endpoint to retrieve a node's status. [417c137](https://github.com/Kong/kong/commit/417c1376c08d3562bebe0c0816c6b54df045f515)
- CLI
  - `$ kong migrations reset` now asks for confirmation. [#365](https://github.com/Kong/kong/pull/365)

#### Fixed

- Plugins
  - Basic authentication not being executed if added to an API with default configuration. [6d732cd](https://github.com/Kong/kong/commit/6d732cd8b0ec92ef328faa843215d8264f50fb75)
  - SSL plugin configuration parsing. [#353](https://github.com/Kong/kong/pull/353)
  - SSL plugin doesn't accept a `consumer_id` anymore, as this wouldn't make sense. [#372](https://github.com/Kong/kong/pull/372) [#322](https://github.com/Kong/kong/pull/322)
  - Authentication plugins now return `401` when missing credentials. [#375](https://github.com/Kong/kong/pull/375) [#354](https://github.com/Kong/kong/pull/354)
- Admin API
  - Non supported HTTP methods now return `405` instead of `500`. [38f1b7f](https://github.com/Kong/kong/commit/38f1b7fa9f45f60c4130ef5ff9fe2c850a2ba586)
  - Prevent PATCH requests from overriding a plugin's configuration if partially updated. [9a7388d](https://github.com/Kong/kong/commit/9a7388d695c9de105917cde23a684a7d6722a3ca)
- Handle occasionally missing `schema_migrations` table. [#365](https://github.com/Kong/kong/pull/365) [#250](https://github.com/Kong/kong/pull/250)

> **internal**
> - DAO:
>   - Complete refactor. No more need for hard-coded queries. [#346](https://github.com/Kong/kong/pull/346)
> - Schemas:
>   - New `self_check` test for schema definitions. [5bfa7ca](https://github.com/Kong/kong/commit/5bfa7ca13561173161781f872244d1340e4152c1)

[Back to TOC](#table-of-contents)

## [0.3.2] - 2015/06/08

#### Fixed

- Uppercase Cassandra keyspace bug that prevented Kong to work with [kongdb.org](http://kongdb.org/)
- Multipart requests not properly parsed in the admin API. [#344](https://github.com/Kong/kong/issues/344)

[Back to TOC](#table-of-contents)

## [0.3.1] - 2015/06/07

#### Fixed

- Schema migrations are now automatic, which was missing from previous releases. [#303](https://github.com/Kong/kong/issues/303)

[Back to TOC](#table-of-contents)

## [0.3.0] - 2015/06/04

#### Added

- Support for SSL.
- Plugins
  - New HTTP logging plugin. [#226](https://github.com/Kong/kong/issues/226) [#251](https://github.com/Kong/kong/pull/251)
  - New SSL plugin.
  - New request size limiting plugin. [#292](https://github.com/Kong/kong/pull/292)
  - Default logging format improvements. [#226](https://github.com/Kong/kong/issues/226) [#262](https://github.com/Kong/kong/issues/262)
  - File logging now logs to a custom file. [#202](https://github.com/Kong/kong/issues/202)
  - Keyauth plugin now defaults `key_names` to "apikey".
- Admin API
  - RESTful routing. Much nicer Admin API routing. Ex: `/apis/{name_or_id}/plugins`. [#98](https://github.com/Kong/kong/issues/98) [#257](https://github.com/Kong/kong/pull/257)
  - Support `PUT` method for endpoints such as `/apis/`, `/apis/plugins/`, `/consumers/`
  - Support for `application/json` and `x-www-form-urlencoded` Content Types for all `PUT`, `POST` and `PATCH` endpoints by passing a `Content-Type` header. [#236](https://github.com/Kong/kong/pull/236)
- Resolver
  - Support resolving APIs by Path as well as by Header. [#192](https://github.com/Kong/kong/pull/192) [#282](https://github.com/Kong/kong/pull/282)
  - Support for `X-Host-Override` as an alternative to `Host` for browsers. [#203](https://github.com/Kong/kong/issues/203) [#246](https://github.com/Kong/kong/pull/246)
- Auth plugins now send user informations to your upstream services. [#228](https://github.com/Kong/kong/issues/228)
- Invalid `target_url` value are now being caught when creating an API. [#149](https://github.com/Kong/kong/issues/149)

#### Fixed

- Uppercase Cassandra keyspace causing migration failure. [#249](https://github.com/Kong/kong/issues/249)
- Guarantee that ratelimiting won't allow requests in case the atomicity of the counter update is not guaranteed. [#289](https://github.com/Kong/kong/issues/289)

> **internal**
> - Schemas:
>   - New property type: `array`. [#277](https://github.com/Kong/kong/pull/277)
>   - Entities schemas now live in their own files and are starting to be unit tested.
>   - Subfields are handled better: (notify required subfields and auto-vivify is subfield has default values).
> - Way faster unit tests. Not resetting the DB anymore between tests.
> - Improved coverage computation (exclude `vendor/`).
> - Travis now lints `kong/`.
> - Way faster Travis setup.
> - Added a new HTTP client for in-nginx usage, using the cosocket API.
> - Various refactorings.
> - Fix [#196](https://github.com/Kong/kong/issues/196).
> - Disabled ipv6 in resolver.

[Back to TOC](#table-of-contents)

## [0.2.1] - 2015/05/12

This is a maintenance release including several bug fixes and usability improvements.

#### Added
- Support for local DNS resolution. [#194](https://github.com/Kong/kong/pull/194)
- Support for Debian 8 and Ubuntu 15.04.
- DAO
  - Cassandra version bumped to 2.1.5
  - Support for Cassandra downtime. If Cassandra goes down and is brought back up, Kong will not need to restart anymore, statements will be re-prepared on-the-fly. This is part of an ongoing effort from [jbochi/lua-resty-cassandra#47](https://github.com/jbochi/lua-resty-cassandra/pull/47), [#146](https://github.com/Kong/kong/pull/146) and [#187](https://github.com/Kong/kong/pull/187).
Queries effectuated during the downtime will still be lost. [#11](https://github.com/Kong/kong/pull/11)
  - Leverage reused sockets. If the DAO reuses a socket, it will not re-set their keyspace. This should give a small but appreciable performance improvement. [#170](https://github.com/Kong/kong/pull/170)
  - Cascade delete plugins configurations when deleting a Consumer or an API associated with it. [#107](https://github.com/Kong/kong/pull/107)
  - Allow Cassandra hosts listening on different ports than the default. [#185](https://github.com/Kong/kong/pull/185)
- CLI
  - Added a notice log when Kong tries to connect to Cassandra to avoid user confusion. [#168](https://github.com/Kong/kong/pull/168)
  - The CLI now tests if the ports are already being used before starting and warns.
- Admin API
  - `name` is now an optional property for APIs. If none is being specified, the name will be the API `public_dns`. [#181](https://github.com/Kong/kong/pull/181)
- Configuration
  - The memory cache size is now configurable. [#208](https://github.com/Kong/kong/pull/208)

#### Fixed
- Resolver
  - More explicit "API not found" message from the resolver if the Host was not found in the system. "API not found with Host: %s".
  - If multiple hosts headers are being sent, Kong will test them all to see if one of the API is in the system. [#186](https://github.com/Kong/kong/pull/186)
- Admin API: responses now have a new line after the body. [#164](https://github.com/Kong/kong/issues/164)
- DAO: keepalive property is now properly passed when Kong calls `set_keepalive` on Cassandra sockets.
- Multipart dependency throwing error at startup. [#213](https://github.com/Kong/kong/pull/213)

> **internal**
> - Separate Migrations from the DAO factory.
> - Update dev config + Makefile rules (`run` becomes `start`).
> - Introducing an `ngx` stub for unit tests and CLI.
> - Switch many PCRE regexes to using patterns.

[Back to TOC](#table-of-contents)

## [0.2.0-2] - 2015/04/27

First public release of Kong. This version brings a lot of internal improvements as well as more usability and a few additional plugins.

#### Added
- Plugins
  - CORS plugin.
  - Request transformation plugin.
  - NGINX plus monitoring plugin.
- Configuration
  - New properties: `proxy_port` and `api_admin_port`. [#142](https://github.com/Kong/kong/issues/142)
- CLI
  - Better info, help and error messages. [#118](https://github.com/Kong/kong/issues/118) [#124](https://github.com/Kong/kong/issues/124)
  - New commands: `kong reload`, `kong quit`. [#114](https://github.com/Kong/kong/issues/114) Alias of `version`: `kong --version` [#119](https://github.com/Kong/kong/issues/119)
  - `kong restart` simply starts Kong if not previously running + better pid file handling. [#131](https://github.com/Kong/kong/issues/131)
- Package distributions: .rpm, .deb and .pkg for easy installs on most common platforms.

#### Fixed
- Admin API: trailing slash is not necessary anymore for core resources such as `/apis` or `/consumers`.
- Leaner default configuration. [#156](https://github.com/Kong/kong/issues/156)

> **internal**
> - All scripts moved to the CLI as "hidden" commands (`kong db`, `kong config`).
> - More tests as always, and they are structured better. The coverage went down mainly because of plugins which will later move to their own repos. We are all eagerly waiting for that!
> - `src/` was renamed to `kong/` for ease of development
> - All system dependencies versions for package building and travis-ci are now listed in `versions.sh`
> - DAO doesn't need to `:prepare()` prior to run queries. Queries can be prepared at runtime. [#146](https://github.com/Kong/kong/issues/146)

[Back to TOC](#table-of-contents)

## [0.1.1beta-2] - 2015/03/30

#### Fixed

- Wrong behavior of auto-migration in `kong start`.

[Back to TOC](#table-of-contents)

## [0.1.0beta-3] - 2015/03/25

First public beta. Includes caching and better usability.

#### Added
- Required Openresty is now `1.7.10.1`.
- Freshly built CLI, rewritten in Lua
- `kong start` using a new DB keyspace will automatically migrate the schema. [#68](https://github.com/Kong/kong/issues/68)
- Anonymous error reporting on Proxy and API. [#64](https://github.com/Kong/kong/issues/64)
- Configuration
  - Simplified configuration file (unified in `kong.yml`).
  - In configuration, `plugins_installed` was renamed to `plugins_available`. [#59](https://github.com/Kong/kong/issues/59)
  - Order of `plugins_available` doesn't matter anymore. [#17](https://github.com/Kong/kong/issues/17)
  - Better handling of plugins: Kong now detects which plugins are configured and if they are installed on the current machine.
  - `bin/kong` now defaults on `/etc/kong.yml` for config and `/var/logs/kong` for output. [#71](https://github.com/Kong/kong/issues/71)
- Proxy: APIs/Consumers caching with expiration for faster authentication.
- Admin API: Plugins now use plain form parameters for configuration. [#70](https://github.com/Kong/kong/issues/70)
- Keep track of already executed migrations. `rollback` now behaves as expected. [#8](https://github.com/Kong/kong/issues/8)

#### Fixed
- `Server` header now sends Kong. [#57](https://github.com/Kong/kong/issues/57)
- migrations not being executed in order on Linux. This issue wasn't noticed until unit testing the migrations because for now we only have 1 migration file.
- Admin API: Errors responses are now sent as JSON. [#58](https://github.com/Kong/kong/issues/58)

> **internal**
> - We now have code linting and coverage.
> - Faker and Migrations instances don't live in the DAO Factory anymore, they are only used in scripts and tests.
> - `scripts/config.lua` allows environment based configurations. `make dev` generates a `kong.DEVELOPMENT.yml` and `kong_TEST.yml`. Different keyspaces and ports.
> - `spec_helpers.lua` allows tests to not rely on the `Makefile` anymore. Integration tests can run 100% from `busted`.
> - Switch integration testing from [httpbin.org] to [mockbin.com].
> - `core` plugin was renamed to `resolver`.

[Back to TOC](#table-of-contents)

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

[Back to TOC](#table-of-contents)

[2.0.0]: https://github.com/Kong/kong/compare/1.5.0...2.0.0
[1.5.0]: https://github.com/Kong/kong/compare/1.4.3...1.5.0
[1.4.3]: https://github.com/Kong/kong/compare/1.4.2...1.4.3
[1.4.2]: https://github.com/Kong/kong/compare/1.4.1...1.4.2
[1.4.1]: https://github.com/Kong/kong/compare/1.4.0...1.4.1
[1.4.0]: https://github.com/Kong/kong/compare/1.3.0...1.4.0
[1.3.0]: https://github.com/Kong/kong/compare/1.2.2...1.3.0
[1.2.2]: https://github.com/Kong/kong/compare/1.2.1...1.2.2
[1.2.1]: https://github.com/Kong/kong/compare/1.2.0...1.2.1
[1.2.0]: https://github.com/Kong/kong/compare/1.1.2...1.2.0
[1.1.2]: https://github.com/Kong/kong/compare/1.1.1...1.1.2
[1.1.1]: https://github.com/Kong/kong/compare/1.1.0...1.1.1
[1.1.0]: https://github.com/Kong/kong/compare/1.0.3...1.1.0
[1.0.3]: https://github.com/Kong/kong/compare/1.0.2...1.0.3
[1.0.2]: https://github.com/Kong/kong/compare/1.0.1...1.0.2
[1.0.1]: https://github.com/Kong/kong/compare/1.0.0...1.0.1
[1.0.0]: https://github.com/Kong/kong/compare/0.15.0...1.0.0
[0.15.0]: https://github.com/Kong/kong/compare/0.14.1...0.15.0
[0.14.1]: https://github.com/Kong/kong/compare/0.14.0...0.14.1
[0.14.0]: https://github.com/Kong/kong/compare/0.13.1...0.14.0
[0.13.1]: https://github.com/Kong/kong/compare/0.13.0...0.13.1
[0.13.0]: https://github.com/Kong/kong/compare/0.12.3...0.13.0
[0.12.3]: https://github.com/Kong/kong/compare/0.12.2...0.12.3
[0.12.2]: https://github.com/Kong/kong/compare/0.12.1...0.12.2
[0.12.1]: https://github.com/Kong/kong/compare/0.12.0...0.12.1
[0.12.0]: https://github.com/Kong/kong/compare/0.11.2...0.12.0
[0.11.2]: https://github.com/Kong/kong/compare/0.11.1...0.11.2
[0.11.1]: https://github.com/Kong/kong/compare/0.11.0...0.11.1
[0.10.4]: https://github.com/Kong/kong/compare/0.10.3...0.10.4
[0.11.0]: https://github.com/Kong/kong/compare/0.10.3...0.11.0
[0.10.3]: https://github.com/Kong/kong/compare/0.10.2...0.10.3
[0.10.2]: https://github.com/Kong/kong/compare/0.10.1...0.10.2
[0.10.1]: https://github.com/Kong/kong/compare/0.10.0...0.10.1
[0.10.0]: https://github.com/Kong/kong/compare/0.9.9...0.10.0
[0.9.9]: https://github.com/Kong/kong/compare/0.9.8...0.9.9
[0.9.8]: https://github.com/Kong/kong/compare/0.9.7...0.9.8
[0.9.7]: https://github.com/Kong/kong/compare/0.9.6...0.9.7
[0.9.6]: https://github.com/Kong/kong/compare/0.9.5...0.9.6
[0.9.5]: https://github.com/Kong/kong/compare/0.9.4...0.9.5
[0.9.4]: https://github.com/Kong/kong/compare/0.9.3...0.9.4
[0.9.3]: https://github.com/Kong/kong/compare/0.9.2...0.9.3
[0.9.2]: https://github.com/Kong/kong/compare/0.9.1...0.9.2
[0.9.1]: https://github.com/Kong/kong/compare/0.9.0...0.9.1
[0.9.0]: https://github.com/Kong/kong/compare/0.8.3...0.9.0
[0.8.3]: https://github.com/Kong/kong/compare/0.8.2...0.8.3
[0.8.2]: https://github.com/Kong/kong/compare/0.8.1...0.8.2
[0.8.1]: https://github.com/Kong/kong/compare/0.8.0...0.8.1
[0.8.0]: https://github.com/Kong/kong/compare/0.7.0...0.8.0
[0.7.0]: https://github.com/Kong/kong/compare/0.6.1...0.7.0
[0.6.1]: https://github.com/Kong/kong/compare/0.6.0...0.6.1
[0.6.0]: https://github.com/Kong/kong/compare/0.5.4...0.6.0
[0.5.4]: https://github.com/Kong/kong/compare/0.5.3...0.5.4
[0.5.3]: https://github.com/Kong/kong/compare/0.5.2...0.5.3
[0.5.2]: https://github.com/Kong/kong/compare/0.5.1...0.5.2
[0.5.1]: https://github.com/Kong/kong/compare/0.5.0...0.5.1
[0.5.0]: https://github.com/Kong/kong/compare/0.4.2...0.5.0
[0.4.2]: https://github.com/Kong/kong/compare/0.4.1...0.4.2
[0.4.1]: https://github.com/Kong/kong/compare/0.4.0...0.4.1
[0.4.0]: https://github.com/Kong/kong/compare/0.3.2...0.4.0
[0.3.2]: https://github.com/Kong/kong/compare/0.3.1...0.3.2
[0.3.1]: https://github.com/Kong/kong/compare/0.3.0...0.3.1
[0.3.0]: https://github.com/Kong/kong/compare/0.2.1...0.3.0
[0.2.1]: https://github.com/Kong/kong/compare/0.2.0-2...0.2.1
[0.2.0-2]: https://github.com/Kong/kong/compare/0.1.1beta-2...0.2.0-2
[0.1.1beta-2]: https://github.com/Kong/kong/compare/0.1.0beta-3...0.1.1beta-2
[0.1.0beta-3]: https://github.com/Kong/kong/compare/2236374d5624ad98ea21340ca685f7584ec35744...0.1.0beta-3
[0.0.1alpha-1]: https://github.com/Kong/kong/compare/ffd70b3101ba38d9acc776038d124f6e2fccac3c...2236374d5624ad98ea21340ca685f7584ec35744
