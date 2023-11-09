# Table of Contents

- [3.4.0](#340)
- [3.3.0](#330)
- [3.2.0](#320)
- [3.1.0](#310)
- [3.0.1](#301)
- [3.0.0](#300)
- [Previous releases](#previous-releases)

## Unreleased

### Additions

#### Core

#### Plugins

### Fixes

#### Core

#### Plugins

### Dependencies

## 3.4.0

### Breaking Changes

- :warning: Alpine packages and Docker images based on Alpine are no longer supported
  [#10926](https://github.com/Kong/kong/pull/10926)
- :warning: Cassandra as a datastore for Kong is no longer supported
  [#10931](https://github.com/Kong/kong/pull/10931)
- Ubuntu 18.04 artifacts are no longer supported as it's EOL
- AmazonLinux 2022 artifacts are renamed to AmazonLinux 2023 according to AWS's decision

### Deprecations

- **CentOS packages are now removed from the release and are no longer supported in future versions.**

### Additions

#### Core

- Enable `expressions` and `traditional_compatible` router flavor in stream subsystem.
  [#11071](https://github.com/Kong/kong/pull/11071)
- Make upstream `host_header` and router `preserve_host` config work in stream tls proxy.
  [#11244](https://github.com/Kong/kong/pull/11244)
- Add beta support for WebAssembly/proxy-wasm
  [#11218](https://github.com/Kong/kong/pull/11218)
- '/schemas' endpoint returns additional information about cross-field validation as part of the schema.
  This should help tools that use the Admin API to perform better client-side validation.
  [#11108](https://github.com/Kong/kong/pull/11108)

#### Kong Manager
- First release of the Kong Manager Open Source Edition.
  [#11131](https://github.com/Kong/kong/pull/11131)

#### Plugins

- **OpenTelemetry**: Support AWS X-Ray propagation header
  The field `header_type`now accepts the `aws` value to handle this specific
  propagation header.
  [11075](https://github.com/Kong/kong/pull/11075)
- **Opentelemetry**: Support the `endpoint` parameter as referenceable.
  [#11220](https://github.com/Kong/kong/pull/11220)
- **Ip-Restriction**: Add TCP support to the plugin.
  Thanks [@scrudge](https://github.com/scrudge) for contributing this change.
  [#10245](https://github.com/Kong/kong/pull/10245)

#### Performance

- In dbless mode, the declarative schema is now fully initialized at startup
  instead of on-demand in the request path. This is most evident in decreased
  response latency when updating configuration via the `/config` API endpoint.
  [#10932](https://github.com/Kong/kong/pull/10932)
- The Prometheus plugin has been optimized to reduce proxy latency impacts during scraping.
  [#10949](https://github.com/Kong/kong/pull/10949)
  [#11040](https://github.com/Kong/kong/pull/11040)
  [#11065](https://github.com/Kong/kong/pull/11065)

### Fixes

#### Core

- Declarative config now performs proper uniqueness checks against its inputs:
  previously, it would silently drop entries with conflicting primary/endpoint
  keys, or accept conflicting unique fields silently.
  [#11199](https://github.com/Kong/kong/pull/11199)
- Fixed a bug that causes `POST /config?flatten_errors=1` to throw an exception
  and return a 500 error under certain circumstances.
  [#10896](https://github.com/Kong/kong/pull/10896)
- Fix a bug when worker consuming dynamic log level setting event and using a wrong reference for notice logging
  [#10897](https://github.com/Kong/kong/pull/10897)
- Added a `User=` specification to the systemd unit definition so that
  Kong can be controlled by systemd again.
  [#11066](https://github.com/Kong/kong/pull/11066)
- Fix a bug that caused sampling rate to be applied to individual spans producing split traces.
  [#11135](https://github.com/Kong/kong/pull/11135)
- Fix a bug that caused spans to not be instrumented with http.status_code when the request was not proxied to an upstream.
  Thanks [@backjo](https://github.com/backjo) for contributing this change.
  [#11152](https://github.com/Kong/kong/pull/11152),
  [#11406](https://github.com/Kong/kong/pull/11406)
- Fix a bug that caused the router to fail in `traditional_compatible` mode when a route with multiple paths and no service was created.
  [#11158](https://github.com/Kong/kong/pull/11158)
- Fix an issue where the router of flavor `expressions` can not work correctly
  when `route.protocols` is set to `grpc` or `grpcs`.
  [#11082](https://github.com/Kong/kong/pull/11082)
- Fix an issue where the router of flavor `expressions` can not configure https redirection.
  [#11166](https://github.com/Kong/kong/pull/11166)
- Added new span attribute `net.peer.name` if balancer_data.hostname is available.
  Thanks [@backjo](https://github.com/backjo) for contributing this change.
  [#10723](https://github.com/Kong/kong/pull/10729)
- Make `kong vault get` CLI command work in dbless mode by injecting the necessary directives into the kong cli nginx.conf.
  [#11127](https://github.com/Kong/kong/pull/11127)
  [#11291](https://github.com/Kong/kong/pull/11291)
- Fix an issue where a crashing Go plugin server process would cause subsequent
  requests proxied through Kong to execute Go plugins with inconsistent configurations.
  The issue only affects scenarios where the same Go plugin is applied to different Route
  or Service entities.
  [#11306](https://github.com/Kong/kong/pull/11306)
- Fix an issue where cluster_cert or cluster_ca_cert is inserted into lua_ssl_trusted_certificate before being base64 decoded.
  [#11385](https://github.com/Kong/kong/pull/11385)
- Update the DNS client to follow configured timeouts in a more predictable manner.  Also fix a corner case in its
  behavior that could cause it to resolve incorrectly during transient network and DNS server failures.
  [#11386](https://github.com/Kong/kong/pull/11386)

#### Admin API

- Fix an issue where `/schemas/plugins/validate` endpoint fails to validate valid plugin configuration
  when the key of `custom_fields_by_lua` contains dot character(s).
  [#11091](https://github.com/Kong/kong/pull/11091)
- Fix an issue with the `/tags/:tag` Admin API returning a JSON object (`{}`) instead of an array (`[]`) for empty data sets.
  [#11213](https://github.com/Kong/kong/pull/11213)

#### Plugins

- **Response Transformer**: fix an issue that plugin does not transform the response body while upstream returns a Content-Type with +json suffix at subtype.
  [#10656](https://github.com/Kong/kong/pull/10656)
- **grpc-gateway**: Fixed an issue that empty (all default value) messages can not be unframed correctly.
  [#10836](https://github.com/Kong/kong/pull/10836)
- **ACME**: Fixed sanity test can't work with "kong" storage in Hybrid mode
  [#10852](https://github.com/Kong/kong/pull/10852)
- **rate-limiting**: Fixed an issue that impact the accuracy with the `redis` policy.
  Thanks [@giovanibrioni](https://github.com/giovanibrioni) for contributing this change.
  [#10559](https://github.com/Kong/kong/pull/10559)
- **Zipkin**: Fixed an issue that traces not being generated correctly when instrumentations are enabled.
  [#10983](https://github.com/Kong/kong/pull/10983)
- **Acme**: Fixed string concatenation on cert renewal errors
  [#11364](https://github.com/Kong/kong/pull/11364)
- Validation for queue related parameters has been
  improved. `max_batch_size`, `max_entries` and `max_bytes` are now
  `integer`s instead of `number`s.  `initial_retry_delay` and
  `max_retry_delay` must now be `number`s greater than 0.001
  (seconds).
  [#10840](https://github.com/Kong/kong/pull/10840)

### Changed

#### Core

- Tracing: new attribute `http.route` added to http request spans.
  [#10981](https://github.com/Kong/kong/pull/10981)
- The default value of `lmdb_map_size` config has been bumped to `2048m`
  from `128m` to accommodate most commonly deployed config sizes in DB-less
  and Hybrid mode.
  [#11047](https://github.com/Kong/kong/pull/11047)
- The default value of `cluster_max_payload` config has been bumped to `16m`
  from `4m` to accommodate most commonly deployed config sizes in Hybrid mode.
  [#11090](https://github.com/Kong/kong/pull/11090)
- Remove kong branding from kong HTML error template.
  [#11150](https://github.com/Kong/kong/pull/11150)
- Drop luasocket in cli
  [#11177](https://github.com/Kong/kong/pull/11177)

#### Status API

- Remove the database information from the status API when operating in dbless
  mode or data plane.
  [#10995](https://github.com/Kong/kong/pull/10995)

### Dependencies

- Bumped lua-resty-openssl from 0.8.20 to 0.8.23
  [#10837](https://github.com/Kong/kong/pull/10837)
  [#11099](https://github.com/Kong/kong/pull/11099)
- Bumped kong-lapis from 1.8.3.1 to 1.14.0.2
  [#10841](https://github.com/Kong/kong/pull/10841)
- Bumped lua-resty-events from 0.1.4 to 0.2.0
  [#10883](https://github.com/Kong/kong/pull/10883)
  [#11083](https://github.com/Kong/kong/pull/11083)
  [#11214](https://github.com/Kong/kong/pull/11214)
- Bumped lua-resty-session from 4.0.3 to 4.0.4
  [#11011](https://github.com/Kong/kong/pull/11011)
- Bumped OpenSSL from 1.1.1t to 3.1.1
  [#10180](https://github.com/Kong/kong/pull/10180)
  [#11140](https://github.com/Kong/kong/pull/11140)
- Bumped pgmoon from 1.16.0 to 1.16.2 (Kong's fork)
  [#11181](https://github.com/Kong/kong/pull/11181)
  [#11229](https://github.com/Kong/kong/pull/11229)
- Bumped atc-router from 1.0.5 to 1.2.0
  [#10100](https://github.com/Kong/kong/pull/10100)
  [#11071](https://github.com/Kong/kong/pull/11071)
- Bumped lua-resty-lmdb from 1.1.0 to 1.3.0
  [#11227](https://github.com/Kong/kong/pull/11227)
- Bumped lua-ffi-zlib from 0.5 to 0.6
  [#11373](https://github.com/Kong/kong/pull/11373)

### Known Issues
- Some referenceable configuration fields, such as the `http_endpoint` field
  of the `http-log` plugin and the `endpoint` field of the `opentelemetry` plugin,
  do not accept reference values due to incorrect field validation.

## 3.3.0

### Breaking Changes

#### Core

- The `traditional_compatible` router mode has been made more compatible with the
  behavior of `traditional` mode by splitting routes with multiple paths into
  multiple atc routes with separate priorities.  Since the introduction of the new
  router in Kong Gateway 3.0, `traditional_compatible` mode assigned only one priority
  to each route, even if different prefix path lengths and regular expressions
  were mixed in a route. This was not how multiple paths were handled in the
  `traditional` router and the behavior has now been changed so that a separate
  priority value is assigned to each path in a route.
  [#10615](https://github.com/Kong/kong/pull/10615)

#### Plugins

- **http-log, statsd, opentelemetry, datadog**: The queueing system
  has been reworked, causing some plugin parameters to not function as expected
  anymore. If you use queues on these plugin, new parameters must be configured.
  The module `kong.tools.batch_queue` has been renamed to `kong.tools.queue` in
  the process and the API was changed.  If your custom plugin uses queues, it must
  be updated to use the new API.
  See
  [this blog post](https://konghq.com/blog/product-releases/reworked-plugin-queues-in-kong-gateway-3-3)
  for a tour of the new queues and how they are parametrized.
  [#10172](https://github.com/Kong/kong/pull/10172)
- **http-log**: If the log server responds with a 3xx HTTP status code, the
  plugin will consider it to be an error and retry according to the retry
  configuration.  Previously, 3xx status codes would be interpreted as success,
  causing the log entries to be dropped.
  [#10172](https://github.com/Kong/kong/pull/10172)
- **Serverless Functions**: `kong.cache` now points to a cache instance that is dedicated to the
  Serverless Functions plugins: it does not provide access to the global kong cache. Access to
  certain fields in kong.configuration has also been restricted.
  [#10417](https://github.com/Kong/kong/pull/10417)
- **Zipkin**: The zipkin plugin now uses queues for internal
  buffering.  The standard queue parameter set is available to
  control queuing behavior.
  [#10753](https://github.com/Kong/kong/pull/10753)
- Tracing: tracing_sampling_rate defaults to 0.01 (trace one of every 100 requests) instead of the previous 1
  (trace all requests). Tracing all requests is inappropriate for most production systems
  [#10774](https://github.com/Kong/kong/pull/10774)
- **Proxy Cache**: Add option to remove the proxy cache headers from the response
  [#10445](https://github.com/Kong/kong/pull/10445)

### Additions

#### Core

- Make runloop and init error response content types compliant with Accept header value
  [#10366](https://github.com/Kong/kong/pull/10366)
- Add a new field `updated_at` for core entities ca_certificates, certificates, consumers,
  targets, upstreams, plugins, workspaces, clustering_data_planes and snis.
  [#10400](https://github.com/Kong/kong/pull/10400)
- Allow configuring custom error templates
  [#10374](https://github.com/Kong/kong/pull/10374)
- The maximum number of request headers, response headers, uri args, and post args that are
  parsed by default can now be configured with a new configuration parameters:
  `lua_max_req_headers`, `lua_max_resp_headers`, `lua_max_uri_args` and `lua_max_post_args`
  [#10443](https://github.com/Kong/kong/pull/10443)
- Allow configuring Labels for data planes to provide metadata information.
  Labels are only compatible with hybrid mode deployments with Kong Konnect (SaaS)
  [#10471](https://github.com/Kong/kong/pull/10471)
- Add Postgres triggers on the core entites and entities in bundled plugins to delete the
  expired rows in an efficient and timely manner.
  [#10389](https://github.com/Kong/kong/pull/10389)
- Support for configurable Node IDs
  [#10385](https://github.com/Kong/kong/pull/10385)
- Request and response buffering options are now enabled for incoming HTTP 2.0 requests too.
  Thanks [@PidgeyBE](https://github.com/PidgeyBE) for contributing this change.
  [#10595](https://github.com/Kong/kong/pull/10595)
  [#10204](https://github.com/Kong/kong/pull/10204)
- Add `KONG_UPSTREAM_DNS_TIME` to `kong.ctx` so that we can record the time it takes for DNS
  resolution when Kong proxies to upstream.
  [#10355](https://github.com/Kong/kong/pull/10355)
- Tracing: rename spans to simplify filtering on tracing backends.
  [#10577](https://github.com/Kong/kong/pull/10577)
- Support timeout for dynamic log level
  [#10288](https://github.com/Kong/kong/pull/10288)
- Added new span attribute `http.client_ip` to capture the client IP when behind a proxy.
  Thanks [@backjo](https://github.com/backjo) for this contribution!
  [#10723](https://github.com/Kong/kong/pull/10723)

#### Admin API

- The `/upstreams/<upstream>/health?balancer_health=1` endpoint always shows the balancer health,
  through a new attribute balancer_health, which always returns HEALTHY or UNHEALTHY (reporting
  the true state of the balancer), even if the overall upstream health status is HEALTHCHECKS_OFF.
  This is useful for debugging.
  [#5885](https://github.com/Kong/kong/pull/5885)

#### Status API

- The `status_listen` server has been enhanced with the addition of the
  `/status/ready` API for monitoring Kong's health.
  This endpoint provides a `200` response upon receiving a `GET` request,
  but only if a valid, non-empty configuration is loaded and Kong is
  prepared to process user requests.
  Load balancers frequently utilize this functionality to ascertain
  Kong's availability to distribute incoming requests.
  [#10610](https://github.com/Kong/kong/pull/10610)
  [#10787](https://github.com/Kong/kong/pull/10787)

#### Plugins

- **ACME**: acme plugin now supports configuring an `account_key` in `keys` and `key_sets`
  [#9746](https://github.com/Kong/kong/pull/9746)
- **Proxy-Cache**: add `ignore_uri_case` to configuring cache-key uri to be handled as lowercase
  [#10453](https://github.com/Kong/kong/pull/10453)
- **HTTP-Log**: add `application/json; charset=utf-8` option for the `Content-Type` header
  in the http-log plugin, for log collectors that require that character set declaration.
  [#10533](https://github.com/Kong/kong/pull/10533)
- **DataDog**: supports value of `host` to be referenceable.
  [#10484](https://github.com/Kong/kong/pull/10484)
- **Zipkin&Opentelemetry**: convert traceid in http response headers to hex format
  [#10534](https://github.com/Kong/kong/pull/10534)
- **ACME**: acme plugin now supports configuring `namespace` for redis storage
  which is default to empty string for backward compatibility.
  [#10562](https://github.com/Kong/kong/pull/10562)
- **AWS Lambda**: add a new field `disable_https` to support scheme config on lambda service api endpoint
  [#9799](https://github.com/Kong/kong/pull/9799)
- **OpenTelemetry**: spans are now correctly correlated in downstream Datadog traces.
  [10531](https://github.com/Kong/kong/pull/10531)
- **OpenTelemetry**: add `header_type` field in OpenTelemetry plugin.
  Previously, the `header_type` was hardcoded to `preserve`, now it can be set to one of the
  following values: `preserve`, `ignore`, `b3`, `b3-single`, `w3c`, `jaeger`, `ot`.
  [#10620](https://github.com/Kong/kong/pull/10620)

#### PDK

- PDK now supports getting plugins' ID with `kong.plugin.get_id`.
  [#9903](https://github.com/Kong/kong/pull/9903)

### Fixes

#### Core

- Fixed an issue where upstream keepalive pool has CRC32 collision.
  [#9856](https://github.com/Kong/kong/pull/9856)
- Fix an issue where control plane does not downgrade config for `aws_lambda` and `zipkin` for older version of data planes.
  [#10346](https://github.com/Kong/kong/pull/10346)
- Fix an issue where control plane does not rename fields correctly for `session` for older version of data planes.
  [#10352](https://github.com/Kong/kong/pull/10352)
- Fix an issue where validation to regex routes may be skipped when the old-fashioned config is used for DB-less Kong.
  [#10348](https://github.com/Kong/kong/pull/10348)
- Fix and issue where tracing may cause unexpected behavior.
  [#10364](https://github.com/Kong/kong/pull/10364)
- Fix an issue where balancer passive healthcheck would use wrong status code when kong changes status code
  from upstream in `header_filter` phase.
  [#10325](https://github.com/Kong/kong/pull/10325)
  [#10592](https://github.com/Kong/kong/pull/10592)
- Fix an issue where schema validations failing in a nested record did not propagate the error correctly.
  [#10449](https://github.com/Kong/kong/pull/10449)
- Fixed an issue where dangling Unix sockets would prevent Kong from restarting in
  Docker containers if it was not cleanly stopped.
  [#10468](https://github.com/Kong/kong/pull/10468)
- Fix an issue where sorting function for traditional router sources/destinations lead to "invalid order
  function for sorting" error.
  [#10514](https://github.com/Kong/kong/pull/10514)
- Fix the UDP socket leak caused by frequent DNS queries.
  [#10691](https://github.com/Kong/kong/pull/10691)
- Fix a typo of mlcache option `shm_set_tries`.
  [#10712](https://github.com/Kong/kong/pull/10712)
- Fix an issue where slow start up of Go plugin server causes dead lock.
  [#10561](https://github.com/Kong/kong/pull/10561)
- Tracing: fix an issue that caused the `sampled` flag of incoming propagation
  headers to be handled incorrectly and only affect some spans.
  [#10655](https://github.com/Kong/kong/pull/10655)
- Tracing: fix an issue that was preventing `http_client` spans to be created for OpenResty HTTP client requests.
  [#10680](https://github.com/Kong/kong/pull/10680)
- Tracing: fix an approximation issue that resulted in reduced precision of the balancer span start and end times.
  [#10681](https://github.com/Kong/kong/pull/10681)
- Tracing: tracing_sampling_rate defaults to 0.01 (trace one of every 100 requests) instead of the previous 1
  (trace all requests). Tracing all requests is inappropriate for most production systems
  [#10774](https://github.com/Kong/kong/pull/10774)
- Fix issue when stopping a Kong could error out if using Vault references
  [#10775](https://github.com/Kong/kong/pull/10775)
- Fix issue where Vault configuration stayed sticky and cached even when configurations were changed.
  [#10776](https://github.com/Kong/kong/pull/10776)
- Backported the openresty `ngx.print` chunk encoding buffer double free bug fix that
  leads to the corruption of chunk-encoded response data.
  [#10816](https://github.com/Kong/kong/pull/10816)
  [#10824](https://github.com/Kong/kong/pull/10824)


#### Admin API

- Fix an issue where empty value of URI argument `custom_id` crashes `/consumer`.
  [#10475](https://github.com/Kong/kong/pull/10475)

#### Plugins

- **Request-Transformer**: fix an issue where requests would intermittently
  be proxied with incorrect query parameters.
  [10539](https://github.com/Kong/kong/pull/10539)
- **Request Transformer**: honor value of untrusted_lua configuration parameter
  [#10327](https://github.com/Kong/kong/pull/10327)
- **OAuth2**: fix an issue that OAuth2 token was being cached to nil while access to the wrong service first.
  [#10522](https://github.com/Kong/kong/pull/10522)
- **OpenTelemetry**: fix an issue that reconfigure of OpenTelemetry does not take effect.
  [#10172](https://github.com/Kong/kong/pull/10172)
- **OpenTelemetry**: fix an issue that caused spans to be propagated incorrectly
  resulting in a wrong hierarchy being rendered on tracing backends.
  [#10663](https://github.com/Kong/kong/pull/10663)
- **gRPC gateway**: `null` in the JSON payload caused an uncaught exception to be thrown during pb.encode.
  [#10687](https://github.com/Kong/kong/pull/10687)
- **Oauth2**: prevent an authorization code created by one plugin instance to be exchanged for an access token by a different plugin instance.
  [#10011](https://github.com/Kong/kong/pull/10011)
- **gRPC gateway**: fixed an issue that empty arrays in JSON are incorrectly encoded as `"{}"`; they are
now encoded as `"[]"` to comply with standard.
  [#10790](https://github.com/Kong/kong/pull/10790)

#### PDK

- Fixed an issue for tracing PDK where sample rate does not work.
  [#10485](https://github.com/Kong/kong/pull/10485)

### Changed

#### Core

- Postgres TTL cleanup timer will now only run on traditional and control plane nodes that have enabled the Admin API.
  [#10405](https://github.com/Kong/kong/pull/10405)
- Postgres TTL cleanup timer now runs a batch delete loop on each ttl enabled table with a number of 50.000 rows per batch.
  [#10407](https://github.com/Kong/kong/pull/10407)
- Postgres TTL cleanup timer now runs every 5 minutes instead of every 60 seconds.
  [#10389](https://github.com/Kong/kong/pull/10389)
- Postgres TTL cleanup timer now deletes expired rows based on database server-side timestamp to avoid potential
  problems caused by the difference of clock time between Kong and database server.
  [#10389](https://github.com/Kong/kong/pull/10389)

#### PDK

- `request.get_uri_captures` now returns the unnamed part tagged as an array (for jsonification).
  [#10390](https://github.com/Kong/kong/pull/10390)

#### Plugins

- **Request-Termination**: If the echo option was used, it would not return the uri-captures.
  [#10390](https://github.com/Kong/kong/pull/10390)
- **OpenTelemetry**: add `http_response_header_for_traceid` field in OpenTelemetry plugin.
  The plugin will set the corresponding header in the response
  if the field is specified with a string value.
  [#10379](https://github.com/Kong/kong/pull/10379)

### Dependencies

- Bumped lua-resty-session from 4.0.2 to 4.0.3
  [#10338](https://github.com/Kong/kong/pull/10338)
- Bumped lua-protobuf from 0.3.3 to 0.5.0
  [#10137](https://github.com/Kong/kong/pull/10413)
  [#10790](https://github.com/Kong/kong/pull/10790)
- Bumped lua-resty-timer-ng from 0.2.3 to 0.2.5
  [#10419](https://github.com/Kong/kong/pull/10419)
  [#10664](https://github.com/Kong/kong/pull/10664)
- Bumped lua-resty-openssl from 0.8.17 to 0.8.20
  [#10463](https://github.com/Kong/kong/pull/10463)
  [#10476](https://github.com/Kong/kong/pull/10476)
- Bumped lua-resty-http from 0.17.0.beta.1 to 0.17.1
  [#10547](https://github.com/Kong/kong/pull/10547)
- Bumped LuaSec from 1.2.0 to 1.3.1
  [#10528](https://github.com/Kong/kong/pull/10528)
- Bumped lua-resty-acme from 0.10.1 to 0.11.0
  [#10562](https://github.com/Kong/kong/pull/10562)
- Bumped lua-resty-events from 0.1.3 to 0.1.4
  [#10634](https://github.com/Kong/kong/pull/10634)
- Bumped lua-kong-nginx-module from 0.5.1 to 0.6.0
  [#10288](https://github.com/Kong/kong/pull/10288)
- Bumped lua-resty-lmdb from 1.0.0 to 1.1.0
  [#10766](https://github.com/Kong/kong/pull/10766)

## 3.2.0

### Breaking Changes

#### Plugins

- **JWT**: JWT plugin now denies a request that has different tokens in the jwt token search locations.
  [#9946](https://github.com/Kong/kong/pull/9946)
- **Session**: for sessions to work as expected it is required that all nodes run Kong >= 3.2.x.
  For that reason it is advisable that during upgrades mixed versions of proxy nodes run for
  as little as possible. During that time, the invalid sessions could cause failures and partial downtime.
  All existing sessions are invalidated when upgrading to this version.
  The parameter `idling_timeout` now has a default value of `900`: unless configured differently,
  sessions expire after 900 seconds (15 minutes) of idling.
  The parameter `absolute_timeout` has a default value of `86400`: unless configured differently,
  sessions expire after 86400 seconds (24 hours).
  [#10199](https://github.com/Kong/kong/pull/10199)
- **Proxy Cache**: Add wildcard and parameter match support for content_type
  [#10209](https://github.com/Kong/kong/pull/10209)

### Additions

#### Core

- Expose postgres connection pool configuration.
  [#9603](https://github.com/Kong/kong/pull/9603)
- When `router_flavor` is `traditional_compatible`, verify routes created using the
  Expression router instead of the traditional router to ensure created routes
  are actually compatible.
  [#9987](https://github.com/Kong/kong/pull/9987)
- Nginx charset directive can now be configured with Nginx directive injections
  [#10111](https://github.com/Kong/kong/pull/10111)
- Services upstream TLS config is extended to stream subsystem.
  [#9947](https://github.com/Kong/kong/pull/9947)
- New configuration option `ssl_session_cache_size` to set the Nginx directive `ssl_session_cache`.
  This config defaults to `10m`.
  Thanks [Michael Kotten](https://github.com/michbeck100) for contributing this change.
  [#10021](https://github.com/Kong/kong/pull/10021)

#### Balancer

- Add a new load-balancing `algorithm` option `latency` to the `Upstream` entity.
  This algorithm will choose a target based on the response latency of each target
  from prior requests.
  [#9787](https://github.com/Kong/kong/pull/9787)

#### Plugins

- **Plugin**: add an optional field `instance_name` that identifies a
  particular plugin entity.
  [#10077](https://github.com/Kong/kong/pull/10077)
- **Zipkin**: Add support to set the durations of Kong phases as span tags
  through configuration property `config.phase_duration_flavor`.
  [#9891](https://github.com/Kong/kong/pull/9891)
- **HTTP logging**: Suppport value of `headers` to be referenceable.
  [#9948](https://github.com/Kong/kong/pull/9948)
- **AWS Lambda**: Add `aws_imds_protocol_version` configuration
  parameter that allows the selection of the IMDS protocol version.
  Defaults to `v1`, can be set to `v2` to enable IMDSv2.
  [#9962](https://github.com/Kong/kong/pull/9962)
- **OpenTelemetry**: Support scoping with services, routes and consumers.
  [#10096](https://github.com/Kong/kong/pull/10096)
- **Statsd**: Add `tag_style` configuration
  parameter that allows to send metrics with [tags](https://github.com/prometheus/statsd_exporter#tagging-extensions).
  Defaults to `nil` which means do not add any tags
  to the metrics.
  [#10118](https://github.com/Kong/kong/pull/10118)
- **Session**: now uses lua-resty-session v4.0.0
  [#10199](https://github.com/Kong/kong/pull/10199)

#### Admin API

- In dbless mode, `/config` API endpoint can now flatten entity-related schema
  validation errors to a single array via the optional `flatten_errors` query
  parameter. Non-entity errors remain unchanged in this mode.
  [#10161](https://github.com/Kong/kong/pull/10161)
  [#10256](https://github.com/Kong/kong/pull/10256)

#### PDK

- Support for `upstream_status` field in log serializer.
  [#10296](https://github.com/Kong/kong/pull/10296)

### Fixes

#### Core

- Add back Postgres `FLOOR` function when calculating `ttl`, so the returned `ttl` is always a whole integer.
  [#9960](https://github.com/Kong/kong/pull/9960)
- Fix an issue where after a valid declarative configuration is loaded,
  the configuration hash is incorrectly set to the value: `00000000000000000000000000000000`.
  [#9911](https://github.com/Kong/kong/pull/9911)
- Update the batch queues module so that queues no longer grow without bounds if
  their consumers fail to process the entries.  Instead, old batches are now dropped
  and an error is logged.
  [#10247](https://github.com/Kong/kong/pull/10247)
- Fix an issue where 'X-Kong-Upstream-Status' cannot be emitted when response is buffered.
  [#10056](https://github.com/Kong/kong/pull/10056)

#### Plugins

- **Zipkin**: Fix an issue where the global plugin's sample ratio overrides route-specific.
  [#9877](https://github.com/Kong/kong/pull/9877)
- **JWT**: Deny requests that have different tokens in the jwt token search locations. Thanks Jackson 'Che-Chun' Kuo from Latacora for reporting this issue.
  [#9946](https://github.com/Kong/kong/pull/9946)
- **Statsd**: Fix a bug in the StatsD plugin batch queue processing where metrics are published multiple times.
  [#10052](https://github.com/Kong/kong/pull/10052)
- **Datadog**: Fix a bug in the Datadog plugin batch queue processing where metrics are published multiple times.
  [#10044](https://github.com/Kong/kong/pull/10044)
- **OpenTelemetry**: Fix non-compliances to specification:
  - For `http.uri` in spans. The field should be full HTTP URI.
    [#10069](https://github.com/Kong/kong/pull/10069)
  - For `http.status_code`. It should be present on spans for requests that have a status code.
    [#10160](https://github.com/Kong/kong/pull/10160)
  - For `http.flavor`. It should be a string value, not a double.
    [#10160](https://github.com/Kong/kong/pull/10160)
- **OpenTelemetry**: Fix a bug that when getting the trace of other formats, the trace ID reported and propagated could be of incorrect length.
    [#10332](https://github.com/Kong/kong/pull/10332)
- **OAuth2**: `refresh_token_ttl` is now limited between `0` and `100000000` by schema validator. Previously numbers that are too large causes requests to fail.
  [#10068](https://github.com/Kong/kong/pull/10068)

### Changed

#### Core

- Improve error message for invalid JWK entities.
  [#9904](https://github.com/Kong/kong/pull/9904)
- Renamed two configuration properties:
    * `opentelemetry_tracing` => `tracing_instrumentations`
    * `opentelemetry_tracing_sampling_rate` => `tracing_sampling_rate`

  The old `opentelemetry_*` properties are considered deprecated and will be
  fully removed in a future version of Kong.
  [#10122](https://github.com/Kong/kong/pull/10122)
  [#10220](https://github.com/Kong/kong/pull/10220)

#### Hybrid Mode

- Revert the removal of WebSocket protocol support for configuration sync,
  and disable the wRPC protocol.
  [#9921](https://github.com/Kong/kong/pull/9921)

### Dependencies

- Bumped luarocks from 3.9.1 to 3.9.2
  [#9942](https://github.com/Kong/kong/pull/9942)
- Bumped atc-router from 1.0.1 to 1.0.5
  [#9925](https://github.com/Kong/kong/pull/9925)
  [#10143](https://github.com/Kong/kong/pull/10143)
  [#10208](https://github.com/Kong/kong/pull/10208)
- Bumped lua-resty-openssl from 0.8.15 to 0.8.17
  [#9583](https://github.com/Kong/kong/pull/9583)
  [#10144](https://github.com/Kong/kong/pull/10144)
- Bumped lua-kong-nginx-module from 0.5.0 to 0.5.1
  [#10181](https://github.com/Kong/kong/pull/10181)
- Bumped lua-resty-session from 3.10 to 4.0.2
  [#10199](https://github.com/Kong/kong/pull/10199)
  [#10230](https://github.com/Kong/kong/pull/10230)
  [#10308](https://github.com/Kong/kong/pull/10308)
- Bumped OpenSSL from 1.1.1s to 1.1.1t
  [#10266](https://github.com/Kong/kong/pull/10266)
- Bumped lua-resty-timer-ng from 0.2.0 to 0.2.3
  [#10265](https://github.com/Kong/kong/pull/10265)


## 3.1.0

### Breaking Changes

#### Core

- Change the reponse body for a TRACE method from `The upstream server responded with 405`
  to `Method not allowed`, make the reponse to show more clearly that Kong do not support
  TRACE method.
  [#9448](https://github.com/Kong/kong/pull/9448)
- Add `allow_debug_header` Kong conf to allow use of the `Kong-Debug` header for debugging.
  This option defaults to `off`.
  [#10054](https://github.com/Kong/kong/pull/10054)
  [#10125](https://github.com/Kong/kong/pull/10125)


### Additions

#### Core

- Allow `kong.conf` ssl properties to be stored in vaults or environment
  variables. Allow such properties to be configured directly as content
  or base64 encoded content.
  [#9253](https://github.com/Kong/kong/pull/9253)
- Add support for full entity transformations in schemas
  [#9431](https://github.com/Kong/kong/pull/9431)
- Allow schema `map` type field being marked as referenceable.
  [#9611](https://github.com/Kong/kong/pull/9611)
- Add support for dynamically changing the log level
  [#9744](https://github.com/Kong/kong/pull/9744)
- Add `keys` entity to store and manage asymmetric keys.
  [#9737](https://github.com/Kong/kong/pull/9737)
- Add `key-sets` entity to group and manage `keys`
  [#9737](https://github.com/Kong/kong/pull/9737)

#### Plugins

- **Rate-limiting**: The HTTP status code and response body for rate-limited
  requests can now be customized. Thanks, [@utix](https://github.com/utix)!
  [#8930](https://github.com/Kong/kong/pull/8930)
- **Zipkin**: add `response_header_for_traceid` field in Zipkin plugin.
  The plugin will set the corresponding header in the response
  if the field is specified with a string value.
  [#9173](https://github.com/Kong/kong/pull/9173)
- **AWS Lambda**: add `requestContext` field into `awsgateway_compatible` input data
  [#9380](https://github.com/Kong/kong/pull/9380)
- **ACME**: add support for Redis SSL, through configuration properties
  `config.storage_config.redis.ssl`, `config.storage_config.redis.ssl_verify`,
  and `config.storage_config.redis.ssl_server_name`.
  [#9626](https://github.com/Kong/kong/pull/9626)
- **Session**: Add new config `cookie_persistent` that allows browser to persist
  cookies even if browser is closed. This defaults to `false` which means
  cookies are not persistend across browser restarts. Thanks [@tschaume](https://github.com/tschaume)
  for this contribution!
  [#8187](https://github.com/Kong/kong/pull/8187)
- **Response-rate-limiting**: add support for Redis SSL, through configuration properties
  `redis_ssl` (can be set to `true` or `false`), `ssl_verify`, and `ssl_server_name`.
  [#8595](https://github.com/Kong/kong/pull/8595)
  Thanks [@dominikkukacka](https://github.com/dominikkukacka)!
- **OpenTelemetry**: add referenceable attribute to the `headers` field
  that could be stored in vaults.
  [#9611](https://github.com/Kong/kong/pull/9611)
- **HTTP-Log**: Support `http_endpoint` field to be referenceable
  [#9714](https://github.com/Kong/kong/pull/9714)
- **rate-limiting**: Add a new configuration `sync_rate` to the `redis` policy,
  which synchronizes metrics to redis periodically instead of on every request.
  [#9538](https://github.com/Kong/kong/pull/9538)


#### Hybrid Mode

- Data plane node IDs will now persist across restarts.
  [#9067](https://github.com/Kong/kong/pull/9067)
- Add HTTP CONNECT forward proxy support for Hybrid Mode connections. New configuration
  options `cluster_use_proxy`, `proxy_server` and `proxy_server_ssl_verify` are added.
  [#9758](https://github.com/Kong/kong/pull/9758)
  [#9773](https://github.com/Kong/kong/pull/9773)

#### Performance

- Increase the default value of `lua_regex_cache_max_entries`, a warning will be thrown
  when there are too many regex routes and `router_flavor` is `traditional`.
  [#9624](https://github.com/Kong/kong/pull/9624)
- Add batch queue into the Datadog and StatsD plugin to reduce timer usage.
  [#9521](https://github.com/Kong/kong/pull/9521)

#### PDK

- Extend `kong.client.tls.request_client_certificate` to support setting
  the Distinguished Name (DN) list hints of the accepted CA certificates.
  [#9768](https://github.com/Kong/kong/pull/9768)

### Fixes

#### Core

- Fix issue where external plugins crashing with unhandled exceptions
  would cause high CPU utilization after the automatic restart.
  [#9384](https://github.com/Kong/kong/pull/9384)
- Fix issue where Zipkin plugin cannot parse OT baggage headers
  due to invalid OT baggage pattern. [#9280](https://github.com/Kong/kong/pull/9280)
- Add `use_srv_name` options to upstream for balancer.
  [#9430](https://github.com/Kong/kong/pull/9430)
- Fix issue in `header_filter` instrumentation where the span was not
  correctly created.
  [#9434](https://github.com/Kong/kong/pull/9434)
- Fix issue in router building where when field contains an empty table,
  the generated expression is invalid.
  [#9451](https://github.com/Kong/kong/pull/9451)
- Fix issue in router rebuilding where when paths field is invalid,
  the router's mutex is not released properly.
  [#9480](https://github.com/Kong/kong/pull/9480)
- Fixed an issue where `kong docker-start` would fail if `KONG_PREFIX` was set to
  a relative path.
  [#9337](https://github.com/Kong/kong/pull/9337)
- Fixed an issue with error-handling and process cleanup in `kong start`.
  [#9337](https://github.com/Kong/kong/pull/9337)

#### Hybrid Mode

- Fixed a race condition that can cause configuration push events to be dropped
  when the first data-plane connection is established with a control-plane
  worker.
  [#9616](https://github.com/Kong/kong/pull/9616)

#### CLI

- Fix slow CLI performance due to pending timer jobs
  [#9536](https://github.com/Kong/kong/pull/9536)

#### Admin API

- Increase the maximum request argument number from `100` to `1000`,
  and return `400` error if request parameters reach the limitation to
  avoid being truncated.
  [#9510](https://github.com/Kong/kong/pull/9510)
- Paging size parameter is now propogated to next page if specified
  in current request.
  [#9503](https://github.com/Kong/kong/pull/9503)
- Non-normalized prefix route path is now rejected. It will also suggest
  how to write the path in normalized form.
  [#9760](https://github.com/Kong/kong/pull/9760)

#### PDK

- Added support for `kong.request.get_uri_captures`
  (`kong.request.getUriCaptures`)
  [#9512](https://github.com/Kong/kong/pull/9512)
- Fixed parameter type of `kong.service.request.set_raw_body`
  (`kong.service.request.setRawBody`), return type of
  `kong.service.response.get_raw_body`(`kong.service.request.getRawBody`),
  and body parameter type of `kong.response.exit` to bytes. Note that old
  version of go PDK is incompatible after this change.
  [#9526](https://github.com/Kong/kong/pull/9526)
- Vault will not call `semaphore:wait` in `init` or `init_worker` phase.
  [#9851](https://github.com/Kong/kong/pull/9851)

#### Plugins

- Add missing `protocols` field to various plugin schemas.
  [#9525](https://github.com/Kong/kong/pull/9525)
- **AWS Lambda**: Fix an issue that is causing inability to
  read environment variables in ECS environment.
  [#9460](https://github.com/Kong/kong/pull/9460)
- **Request-Transformer**: fix a bug when header renaming will override
  existing header and cause unpredictable result.
  [#9442](https://github.com/Kong/kong/pull/9442)
- **OpenTelemetry**:
  - Fix an issue that the default propagation header
    is not configured to `w3c` correctly.
    [#9457](https://github.com/Kong/kong/pull/9457)
  - Replace the worker-level table cache with
    `BatchQueue` to avoid data race.
    [#9504](https://github.com/Kong/kong/pull/9504)
  - Fix an issue that the `parent_id` is not set
    on the span when propagating w3c traceparent.
    [#9628](https://github.com/Kong/kong/pull/9628)
- **Response-Transformer**: Fix the bug that Response-Transformer plugin
  breaks when receiving an unexcepted body.
  [#9463](https://github.com/Kong/kong/pull/9463)
- **HTTP-Log**: Fix an issue where queue id serialization
  does not include `queue_size` and `flush_timeout`.
  [#9789](https://github.com/Kong/kong/pull/9789)

### Changed

#### Hybrid Mode

- The legacy hybrid configuration protocol has been removed in favor of the wRPC
  protocol introduced in 3.0.
  [#9740](https://github.com/Kong/kong/pull/9740)

### Dependencies

- Bumped openssl from 1.1.1q to 1.1.1s
  [#9674](https://github.com/Kong/kong/pull/9674)
- Bumped atc-router from 1.0.0 to 1.0.1
  [#9558](https://github.com/Kong/kong/pull/9558)
- Bumped lua-resty-openssl from 0.8.10 to 0.8.15
  [#9583](https://github.com/Kong/kong/pull/9583)
  [#9600](https://github.com/Kong/kong/pull/9600)
  [#9675](https://github.com/Kong/kong/pull/9675)
- Bumped lyaml from 6.2.7 to 6.2.8
  [#9607](https://github.com/Kong/kong/pull/9607)
- Bumped lua-resty-acme from 0.8.1 to 0.9.0
  [#9626](https://github.com/Kong/kong/pull/9626)
- Bumped resty.healthcheck from 1.6.1 to 1.6.2
  [#9778](https://github.com/Kong/kong/pull/9778)
- Bumped pgmoon from 1.15.0 to 1.16.0
  [#9815](https://github.com/Kong/kong/pull/9815)


## [3.0.1]

### Fixes

#### Core

- Fix issue where Zipkin plugin cannot parse OT baggage headers
  due to invalid OT baggage pattern. [#9280](https://github.com/Kong/kong/pull/9280)
- Fix issue in `header_filter` instrumentation where the span was not
  correctly created.
  [#9434](https://github.com/Kong/kong/pull/9434)
- Fix issue in router building where when field contains an empty table,
  the generated expression is invalid.
  [#9451](https://github.com/Kong/kong/pull/9451)
- Fix issue in router rebuilding where when paths field is invalid,
  the router's mutex is not released properly.
  [#9480](https://github.com/Kong/kong/pull/9480)
- Fixed an issue where `kong docker-start` would fail if `KONG_PREFIX` was set to
  a relative path.
  [#9337](https://github.com/Kong/kong/pull/9337)
- Fixed an issue with error-handling and process cleanup in `kong start`.
  [#9337](https://github.com/Kong/kong/pull/9337)


## [3.0.0]

> Released 2022/09/12

This major release adds a new router written in Rust and a tracing API
that is compatible with the OpenTelemetry API spec.  Furthermore,
various internal changes have been made to improve Kong's performance
and memory consumption.  As it is a major release, users are advised
to review the list of braking changes to determine whether
configuration changes are needed when upgrading.

### Breaking Changes

#### Deployment

- Blue-green deployment from Kong earlier than `2.1.0` is not supported, upgrade to
  `2.1.0` or later before upgrading to `3.0.0` to have blue-green deployment.
  Thank you [@marc-charpentier]((https://github.com/charpentier)) for reporting issue
  and proposing a pull-request.
  [#8896](https://github.com/Kong/kong/pull/8896)
- Deprecate/stop producing Amazon Linux (1) containers and packages (EOLed December 31, 2020)
  [Kong/docs.konghq.com #3966](https://github.com/Kong/docs.konghq.com/pull/3966)
- Deprecate/stop producing Debian 8 "Jessie" containers and packages (EOLed June 2020)
  [Kong/kong-build-tools #448](https://github.com/Kong/kong-build-tools/pull/448)
  [Kong/kong-distributions #766](https://github.com/Kong/kong-distributions/pull/766)

#### Core


- Kong schema library's `process_auto_fields` function will not any more make a deep
  copy of data that is passed to it when the given context is `"select"`. This was
  done to avoid excessive deep copying of tables where we believe the data most of
  the time comes from a driver like `pgmoon` or `lmdb`. If a custom plugin relied
  on `process_auto_fields` not overriding the given table, it must make its own copy
  before passing it to the function now.
  [#8796](https://github.com/Kong/kong/pull/8796)
- The deprecated `shorthands` field in Kong Plugin or DAO schemas was removed in favor
  or the typed `shorthand_fields`. If your custom schemas still use `shorthands`, you
  need to update them to use `shorthand_fields`.
  [#8815](https://github.com/Kong/kong/pull/8815)
- The support for `legacy = true/false` attribute was removed from Kong schemas and
  Kong field schemas.
  [#8958](https://github.com/Kong/kong/pull/8958)
- The deprecated alias of `Kong.serve_admin_api` was removed. If your custom Nginx
  templates still use it, please change it to `Kong.admin_content`.
  [#8815](https://github.com/Kong/kong/pull/8815)
- The Kong singletons module `"kong.singletons"` was removed in favor of the PDK `kong.*`.
  [#8874](https://github.com/Kong/kong/pull/8874)
- The dataplane config cache was removed. The config persistence is now done automatically with LMDB.
  [#8704](https://github.com/Kong/kong/pull/8704)
- `ngx.ctx.balancer_address` does not exist anymore, please use `ngx.ctx.balancer_data` instead.
  [#9043](https://github.com/Kong/kong/pull/9043)
- We have changed the normalization rules for `route.path`: Kong stores the unnormalized path, but
  regex path always pattern matches with the normalized URI. We used to replace percent-encoding
  in regex path pattern to ensure different forms of URI matches.
  That is no longer supported. Except for reserved characters defined in
  [rfc3986](https://datatracker.ietf.org/doc/html/rfc3986#section-2.2),
  we should write all other characters without percent-encoding.
  [#9024](https://github.com/Kong/kong/pull/9024)
- Kong will no longer use an heuristic to guess whether a `route.path` is a regex pattern. From now 3.0 onwards,
  all regex paths must start with the `"~"` prefix, and all paths that don't start with `"~"` will be considered plain text.
  The migration process should automatically convert the regex paths when upgrading from 2.x to 3.0
  [#9027](https://github.com/Kong/kong/pull/9027)
- Bumping version number (`_format_version`) of declarative configuration to "3.0" for changes on `route.path`.
  Declaritive configuration with older version are upgraded to "3.0" on the fly.
  [#9078](https://github.com/Kong/kong/pull/9078)
- Removed deprecated `config.functions` from serverless-functions plugin's schema,
  please use `config.access` phase instead.
  [#8559](https://github.com/Kong/kong/pull/8559)
- Tags may now contain space characters.
  [#9143](https://github.com/Kong/kong/pull/9143)
- The [Secrets Management](https://docs.konghq.com/gateway/latest/plan-and-deploy/security/secrets-management/)
  feature, which has been in beta since release 2.8.0, is now included as a regular feature.
  [#8871](https://github.com/Kong/kong/pull/8871)
  [#9217](https://github.com/Kong/kong/pull/9217)

#### Admin API

- `POST` requests on Targets endpoint are no longer able to update
  existing entities, they are only able to create new ones.
  [#8596](https://github.com/Kong/kong/pull/8596),
  [#8798](https://github.com/Kong/kong/pull/8798). If you have scripts that use
  `POST` requests to modify Targets, you should change them to `PUT`
  requests to the appropriate endpoints before updating to Kong 3.0.
- Insert and update operations on duplicated Targets returns 409.
  [#8179](https://github.com/Kong/kong/pull/8179),
  [#8768](https://github.com/Kong/kong/pull/8768)
- The list of reported plugins available on the server now returns a table of
  metadata per plugin instead of a boolean `true`.
  [#8810](https://github.com/Kong/kong/pull/8810)

#### PDK

- The `kong.request.get_path()` PDK function now performs path normalization
  on the string that is returned to the caller. The raw, non-normalized version
  of the request path can be fetched via `kong.request.get_raw_path()`.
  [#8823](https://github.com/Kong/kong/pull/8823)
- `pdk.response.set_header()`, `pdk.response.set_headers()`, `pdk.response.exit()` now ignore and emit warnings for manually set `Transfer-Encoding` headers.
  [#8698](https://github.com/Kong/kong/pull/8698)
- The PDK is no longer versioned
  [#8585](https://github.com/Kong/kong/pull/8585)
- The JavaScript PDK now returns `Uint8Array` for `kong.request.getRawBody`,
  `kong.response.getRawBody` and `kong.service.response.getRawBody`. The Python PDK returns `bytes` for `kong.request.get_raw_body`,
  `kong.response.get_raw_body`, `kong.service.response.get_raw_body`. All these funtions used to return strings in the past.
  [#8623](https://github.com/Kong/kong/pull/8623)

#### Plugins

- DAOs in plugins must be listed in an array, so that their loading order is explicit. Loading them in a
  hash-like table is no longer supported.
  [#8988](https://github.com/Kong/kong/pull/8988)
- Plugins MUST now have a valid `PRIORITY` (integer) and `VERSION` ("x.y.z" format)
  field in their `handler.lua` file, otherwise the plugin will fail to load.
  [#8836](https://github.com/Kong/kong/pull/8836)
- The old `kong.plugins.log-serializers.basic` library was removed in favor of the PDK
  function `kong.log.serialize`, please upgrade your plugins to use PDK.
  [#8815](https://github.com/Kong/kong/pull/8815)
- The support for deprecated legacy plugin schemas was removed. If your custom plugins
  still use the old (`0.x era`) schemas, you are now forced to upgrade them.
  [#8815](https://github.com/Kong/kong/pull/8815)
- Some plugins received new priority values.
  This is important for those who run custom plugins as it may affect the sequence your plugins are executed.
  Note that this does not change the order of execution for plugins in a standard kong installation.
  List of plugins and their old and new priority value:
  - `acme` changed from 1007 to 1705
  - `basic-auth` changed from 1001 to 1100
  - `hmac-auth` changed from 1000 to 1030
  - `jwt` changed from 1005 to 1450
  - `key-auth` changed from 1003 to 1250
  - `ldap-auth` changed from 1002 to 1200
  - `oauth2` changed from 1004 to 1400
  - `rate-limiting` changed from 901 to 910
- **HTTP-log**: `headers` field now only takes a single string per header name,
  where it previously took an array of values
  [#6992](https://github.com/Kong/kong/pull/6992)
- **AWS Lambda**: `aws_region` field must be set through either plugin config or environment variables,
  allow both `host` and `aws_region` fields, and always apply SigV4 signature.
  [#8082](https://github.com/Kong/kong/pull/8082)
- **Serverless Functions** Removed deprecated `config.functions`,
  please use `config.access` instead.
  [#8559](https://github.com/Kong/kong/pull/8559)
- **Serverless Functions**: The pre-functions plugin changed priority from `+inf` to `1000000`.
  [#8836](https://github.com/Kong/kong/pull/8836)
- **JWT**: The authenticated JWT is no longer put into the nginx
  context (ngx.ctx.authenticated_jwt_token).  Custom plugins which depend on that
  value being set under that name must be updated to use Kong's shared context
  instead (kong.ctx.shared.authenticated_jwt_token) before upgrading to 3.0
- **Prometheus**: The prometheus metrics have been reworked extensively for 3.0.
  - Latency has been split into 4 different metrics: kong_latency_ms, upstream_latency_ms and request_latency_ms (http) /tcp_session_duration_ms (stream). Buckets details below.
  - Separate out Kong Latency Bucket values and Upstream Latency Bucket values.
  - `consumer_status` removed.
  - `request_count` and `consumer_status` have been merged into just `http_requests_total`. If the `per_consumer` config is set false, the consumer label will be empty.
     If the `per_consumer` config is true, it will be filled.
  - `http_requests_total` has a new label `source`, set to either `exit`, `error` or `service`.
  - New Metric: `node_info`. Single gauge set to 1 that outputs the node's id and kong version.
  - All Memory metrics have a new label `node_id`
  - `nginx_http_current_connections` merged with `nginx_stream_current_connection` into `nginx_current_connections`
  [#8712](https://github.com/Kong/kong/pull/8712)
- **Prometheus**: The plugin doesn't export status codes, latencies, bandwidth and upstream
  healthcheck metrics by default. They can still be turned on manually by setting `status_code_metrics`,
  `latency_metrics`, `bandwidth_metrics` and `upstream_health_metrics` respectively. Enabling those metrics will impact the performance if you have a large volume of Kong entities, we recommend using the [statsd](https://github.com/Kong/kong/tree/master/kong/plugins/statsd) plugin with the push model if that is the case. And now `prometheus` plugin new grafana [dashboard](https://grafana.com/grafana/dashboards/7424-kong-official/) updated
  [#9028](https://github.com/Kong/kong/pull/9028)
- **ACME**: `allow_any_domain` field added. It is default to false and if set to true, the gateway will
  ignore the `domains` field.
  [#9047](https://github.com/Kong/kong/pull/9047)
- **Statsd**:
  - The metric name that is related to the service has been renamed by adding a `service.` prefix. e.g. `kong.service.<service_identifier>.request.count` [#9046](https://github.com/Kong/kong/pull/9046)
  - The metric `kong.<service_identifier>.request.status.<status>` and `kong.<service_identifier>.user.<consumer_identifier>.request.status.<status>` has been renamed to `kong.service.<service_identifier>.status.<status>` and  `kong.service.<service_identifier>.user.<consumer_identifier>.status.<status>` [#9046](https://github.com/Kong/kong/pull/9046)
  - The metric `*.status.<status>.total` from metrics `status_count` and `status_count_per_user` has been removed [#9046](https://github.com/Kong/kong/pull/9046)
- **Proxy-cache**: The plugin does not store the response data in
  `ngx.ctx.proxy_cache_hit` anymore. Logging plugins that need the response data
  must read it from `kong.ctx.shared.proxy_cache_hit` from Kong 3.0 on.
  [#8607](https://github.com/Kong/kong/pull/8607)
- **Rate-limiting**: The default policy is now `local` for all deployment modes.
  [#9344](https://github.com/Kong/kong/pull/9344)
- **Response-rate-limiting**: The default policy is now `local` for all deployment modes.
  [#9344](https://github.com/Kong/kong/pull/9344)

### Deprecations

- The `go_pluginserver_exe` and `go_plugins_dir` directives are no longer supported.
  [#8552](https://github.com/Kong/kong/pull/8552). If you are using
  [Go plugin server](https://github.com/Kong/go-pluginserver), please migrate your plugins to use the
  [Go PDK](https://github.com/Kong/go-pdk) before upgrading.
- The migration helper library (mostly used for Cassandra migrations) is no longer supplied with Kong
  [#8781](https://github.com/Kong/kong/pull/8781)
- The path_handling algorithm `v1` is deprecated and only supported when `router_flavor` config option
  is set to `traditional`.
  [#9290](https://github.com/Kong/kong/pull/9290)

#### Configuration

- The Kong constant `CREDENTIAL_USERNAME` with value of `X-Credential-Username` was
  removed. Kong plugins in general have moved (since [#5516](https://github.com/Kong/kong/pull/5516))
  to use constant `CREDENTIAL_IDENTIFIER` with value of `X-Credential-Identifier` when
  setting  the upstream headers for a credential.
  [#8815](https://github.com/Kong/kong/pull/8815)
- Change the default of `lua_ssl_trusted_certificate` to `system`
  [#8602](https://github.com/Kong/kong/pull/8602) to automatically load trusted CA list from system CA store.
- Remove a warning of `AAAA` being experimental with `dns_order`.
- It is no longer possible to use a .lua format to import a declarative config from the `kong`
  command-line tool, only json and yaml are supported. If your update procedure with kong involves
  executing `kong config db_import config.lua`, please create a `config.json` or `config.yml` and
  use that before upgrading.
  [#8898](https://github.com/Kong/kong/pull/8898)
- We bumped the version number (`_format_version`) of declarative configuration to "3.0" because of changes on `route.path`.
  Declarative configuration with older version shoudl be upgraded to "3.0" on the fly.
  [#9078](https://github.com/Kong/kong/pull/9078)

#### Migrations

- Postgres migrations can now have an `up_f` part like Cassandra
  migrations, designating a function to call.  The `up_f` part is
  invoked after the `up` part has been executed against the database
  for both Postgres and Cassandra.
- A new CLI command, `kong migrations status`, generates the status on a JSON file.

### Dependencies

- Bumped OpenResty from 1.19.9.1 to [1.21.4.1](https://openresty.org/en/changelog-1021004.html)
  [#8850](https://github.com/Kong/kong/pull/8850)
- Bumped pgmoon from 1.13.0 to 1.15.0
  [#8908](https://github.com/Kong/kong/pull/8908)
  [#8429](https://github.com/Kong/kong/pull/8429)
- Bumped OpenSSL from 1.1.1n to 1.1.1q
  [#9074](https://github.com/Kong/kong/pull/9074)
  [#8544](https://github.com/Kong/kong/pull/8544)
  [#8752](https://github.com/Kong/kong/pull/8752)
  [#8994](https://github.com/Kong/kong/pull/8994)
- Bumped resty.openssl from 0.8.8 to 0.8.10
  [#8592](https://github.com/Kong/kong/pull/8592)
  [#8753](https://github.com/Kong/kong/pull/8753)
  [#9023](https://github.com/Kong/kong/pull/9023)
- Bumped inspect from 3.1.2 to 3.1.3
  [#8589](https://github.com/Kong/kong/pull/8589)
- Bumped resty.acme from 0.7.2 to 0.8.1
  [#8680](https://github.com/Kong/kong/pull/8680)
  [#9165](https://github.com/Kong/kong/pull/9165)
- Bumped luarocks from 3.8.0 to 3.9.1
  [#8700](https://github.com/Kong/kong/pull/8700)
  [#9204](https://github.com/Kong/kong/pull/9204)
- Bumped luasec from 1.0.2 to 1.2.0
  [#8754](https://github.com/Kong/kong/pull/8754)
  [#8754](https://github.com/Kong/kong/pull/9205)
- Bumped resty.healthcheck from 1.5.0 to 1.6.1
  [#8755](https://github.com/Kong/kong/pull/8755)
  [#9018](https://github.com/Kong/kong/pull/9018)
  [#9150](https://github.com/Kong/kong/pull/9150)
- Bumped resty.cassandra from 1.5.1 to 1.5.2
  [#8845](https://github.com/Kong/kong/pull/8845)
- Bumped penlight from 1.12.0 to 1.13.1
  [#9206](https://github.com/Kong/kong/pull/9206)
- Bumped lua-resty-mlcache from 2.5.0 to 2.6.0
  [#9287](https://github.com/Kong/kong/pull/9287)

### Additions

#### Performance

- Do not register unnecessary event handlers on Hybrid mode Control Plane
  nodes [#8452](https://github.com/Kong/kong/pull/8452).
- Use the new timer library to improve performance,
  except for the plugin server.
  [#8912](https://github.com/Kong/kong/pull/8912)
- Increased use of caching for DNS queries by activating `additional_section` by default
  [#8895](https://github.com/Kong/kong/pull/8895)
- `pdk.request.get_header` changed to a faster implementation, not to fetch all headers every time it's called
  [#8716](https://github.com/Kong/kong/pull/8716)
- Conditional rebuilding of router, plugins iterator and balancer on DP
  [#8519](https://github.com/Kong/kong/pull/8519),
  [#8671](https://github.com/Kong/kong/pull/8671)
- Made config loading code more cooperative by yielding
  [#8888](https://github.com/Kong/kong/pull/8888)
- Use LuaJIT encoder instead of JSON to serialize values faster in LMDB
  [#8942](https://github.com/Kong/kong/pull/8942)
- Move inflating and JSON decoding non-concurrent, which avoids blocking and makes DP reloads faster
  [#8959](https://github.com/Kong/kong/pull/8959)
- Stop duplication of some events
  [#9082](https://github.com/Kong/kong/pull/9082)
- Improve performance of config hash calculation by using string buffer and tablepool
  [#9073](https://github.com/Kong/kong/pull/9073)
- Reduce cache usage in dbless by not using the kong cache for Routes and Services in LMDB
  [#8972](https://github.com/Kong/kong/pull/8972)


#### Core

- Implemented delayed response in stream mode
  [#6878](https://github.com/Kong/kong/pull/6878)
- Added `cache_key` on target entity for uniqueness detection.
  [#8179](https://github.com/Kong/kong/pull/8179)
- Introduced the tracing API which compatible with OpenTelemetry API spec and
  add build-in instrumentations.
  The tracing API is intend to be used with a external exporter plugin.
  Build-in instrumentation types and sampling rate are configuable through
  `opentelemetry_tracing` and `opentelemetry_tracing_sampling_rate` options.
  [#8724](https://github.com/Kong/kong/pull/8724)
- Added `path`, `uri_capture`, and `query_arg` options to upstream `hash_on`
  for load balancing.
  [#8701](https://github.com/Kong/kong/pull/8701)
- Introduced unix domain socket based `lua-resty-events` to
  replace shared memory based `lua-resty-worker-events`.
  [#8890](https://github.com/Kong/kong/pull/8890)
- Introduced a new router implementation `atc-router`,
  which is written in Rust.
  [#8938](https://github.com/Kong/kong/pull/8938)
- Introduce a new field for entities `table_name` that allows to specify a
  table name. Before the name was deduced by the entity `name` attribute.
  [#9182](https://github.com/Kong/kong/pull/9182)
- Added `headers` on active healthcheck for upstreams.
  [#8255](https://github.com/Kong/kong/pull/8255)
- Target entities using hostnames were resolved when they were not needed. Now
  when a target is removed or updated, the DNS record associated with it is
  removed from the list of hostnames to be resolved.
  [#8497](https://github.com/Kong/kong/pull/8497) [9265](https://github.com/Kong/kong/pull/9265)
- Improved error handling and debugging info in the DNS code
  [#8902](https://github.com/Kong/kong/pull/8902)
- Kong will now attempt to recover from an unclean shutdown by detecting and
  removing dangling unix sockets in the prefix directory
  [#9254](https://github.com/Kong/kong/pull/9254)

#### Admin API

- Added a new API `/timers` to get the timer statistics.
  [#8912](https://github.com/Kong/kong/pull/8912)
  and worker info
  [#8999](https://github.com/Kong/kong/pull/8999)
- `/` endpoint now includes plugin priority
  [#8821](https://github.com/Kong/kong/pull/8821)

#### Hybrid Mode

- Add wRPC protocol support. Now configuration synchronization is over wRPC.
  wRPC is an RPC protocol that encodes with ProtoBuf and transports
  with WebSocket.
  [#8357](https://github.com/Kong/kong/pull/8357)
- To keep compatibility with earlier versions,
  add support for CP to fall back to the previous protocol to support old DP.
  [#8834](https://github.com/Kong/kong/pull/8834)
- Add support to negotiate services supported with wRPC protocol.
  We will support more services than config sync over wRPC in the future.
  [#8926](https://github.com/Kong/kong/pull/8926)
- Declarative config exports happen inside a transaction in Postgres
  [#8586](https://github.com/Kong/kong/pull/8586)

#### Plugins

- Sync all plugin versions to the Kong version
  [#8772](https://github.com/Kong/kong/pull/8772)
- Introduced the new **OpenTelemetry** plugin that export tracing instrumentations
  to any OTLP/HTTP compatible backend.
  `opentelemetry_tracing` configuration should be enabled to collect
  the core tracing spans of Kong.
  [#8826](https://github.com/Kong/kong/pull/8826)
- **Zipkin**: add support for including HTTP path in span name
  through configuration property `http_span_name`.
  [#8150](https://github.com/Kong/kong/pull/8150)
- **Zipkin**: add support for socket connect and send/read timeouts
  through configuration properties `connect_timeout`, `send_timeout`,
  and `read_timeout`. This can help mitigate `ngx.timer` saturation
  when upstream collectors are unavailable or slow.
  [#8735](https://github.com/Kong/kong/pull/8735)
- **AWS-Lambda**: add support for cross account invocation through
  configuration properties `aws_assume_role_arn` and
  `aws_role_session_name`.[#8900](https://github.com/Kong/kong/pull/8900)
  [#8900](https://github.com/Kong/kong/pull/8900)
- **AWS-Lambda**: accept string type `statusCode` as valid return when
  working in proxy integration mode.
  [#8765](https://github.com/Kong/kong/pull/8765)
- **AWS-Lambda**: separate aws credential cache by IAM role ARN
  [#8907](https://github.com/Kong/kong/pull/8907)
- **Statsd**: :fireworks: **Newly open-sourced plugin capabilities**: All capabilities of [Statsd Advanced](https://docs.konghq.com/hub/kong-inc/statsd-advanced/) are now bundled in [Statsd](https://docs.konghq.com/hub/kong-inc/statsd).
  [#9046](https://github.com/Kong/kong/pull/9046)

#### Configuration

- A new configuration item (`openresty_path`) has been added to allow
  developers/operators to specify the OpenResty installation to use when
  running Kong (instead of using the system-installed OpenResty)
  [#8412](https://github.com/Kong/kong/pull/8412)
- Add `ipv6only` to listen options (e.g. `KONG_PROXY_LISTEN`)
  [#9225](https://github.com/Kong/kong/pull/9225)
- Add `so_keepalive` to listen options (e.g. `KONG_PROXY_LISTEN`)
  [#9225](https://github.com/Kong/kong/pull/9225)
- Add LMDB dbless config persistence and removed the JSON based
  config cache for faster startup time
  [#8670](https://github.com/Kong/kong/pull/8670)
- `nginx_events_worker_connections=auto` has a lower bound of 1024
  [#9276](https://github.com/Kong/kong/pull/9276)
- `nginx_main_worker_rlimit_nofile=auto` has a lower bound of 1024
  [#9276](https://github.com/Kong/kong/pull/9276)

#### PDK

- Added new PDK function: `kong.request.get_start_time()`
  [#8688](https://github.com/Kong/kong/pull/8688)
- `kong.db.*.cache_key()` falls back to `.id` if nothing from `cache_key` is found
  [#8553](https://github.com/Kong/kong/pull/8553)

### Fixes

#### Core

- The schema validator now correctly converts `null` from declarative
  configurations to `nil`.
  [#8483](https://github.com/Kong/kong/pull/8483)
- Only reschedule router and plugin iterator timers after finishing previous
  execution, avoiding unnecessary concurrent executions.
  [#8567](https://github.com/Kong/kong/pull/8567)
- External plugins now handle returned JSON with null member correctly.
  [#8611](https://github.com/Kong/kong/pull/8611)
- Fixed an issue where the address of the environ variable could change but the code didn't
  assumed it was fixed after init
  [#8581](https://github.com/Kong/kong/pull/8581)
- Fix issue where the Go plugin server instance would not be updated after
  a restart (e.g., upon a plugin server crash).
  [#8547](https://github.com/Kong/kong/pull/8547)
- Fixed an issue on trying to reschedule the DNS resolving timer when Kong was
  being reloaded.
  [#8702](https://github.com/Kong/kong/pull/8702)
- The private stream API has been rewritten to allow for larger message payloads
  [#8641](https://github.com/Kong/kong/pull/8641)
- Fixed an issue that the client certificate sent to upstream was not updated when calling PATCH Admin API
  [#8934](https://github.com/Kong/kong/pull/8934)
- Fixed an issue where the CP and wRPC modules would cause Kong to crash when calling `export_deflated_reconfigure_payload` without a pcall
  [#8668](https://github.com/Kong/kong/pull/8668)
- Moved all `.proto` files to `/usr/local/kong/include` and ordered by priority.
  [#8914](https://github.com/Kong/kong/pull/8914)
- Fixed an issue that cause unexpected 404 error on creating/updating configs with invalid options
  [#8831](https://github.com/Kong/kong/pull/8831)
- Fixed an issue that causes crashes when calling some PDK APIs
  [#8604](https://github.com/Kong/kong/pull/8604)
- Fixed an issue that cause crashes when go PDK calls return arrays
  [#8891](https://github.com/Kong/kong/pull/8891)
- Plugin servers now shutdowns gracefully when Kong exits
  [#8923](https://github.com/Kong/kong/pull/8923)
- CLI now prompts with `[y/n]` instead of `[Y/n]`, as it does not take `y` as default
  [#9114](https://github.com/Kong/kong/pull/9114)
- Improved the error message when Kong cannot connect to Cassandra on init
  [#8847](https://github.com/Kong/kong/pull/8847)
- Fixed an issue where Vault Subschema wasn't loaded in `off` strategy
  [#9174](https://github.com/Kong/kong/pull/9174)
- The Schema now runs select transformations before process_auto_fields
  [#9049](https://github.com/Kong/kong/pull/9049)
- Fixed an issue where Kong would use too many timers to keep track of upstreams when `worker_consistency`=`eventual`
  [#8694](https://github.com/Kong/kong/pull/8694),
  [#8858](https://github.com/Kong/kong/pull/8858)
- Fixed an issue where it wasn't possible to set target status using only a hostname for targets set only by their hostname
  [#8797](https://github.com/Kong/kong/pull/8797)
- Fixed pagination issue when getting to the second page while iterationg over a foreign key field using the DAO
  [#9255](https://github.com/Kong/kong/pull/9255)
- Fixed an issue where cache entries of some entities were not being properly invalidated after a cascade delete
  [#9261](https://github.com/Kong/kong/pull/9261)
- Running `kong start` when Kong is already running will no longer clobber
  the existing `.kong_env` file [#9254](https://github.com/Kong/kong/pull/9254)


#### Admin API

- Support HTTP/2 when requesting `/status`
  [#8690](https://github.com/Kong/kong/pull/8690)

#### Plugins

- Plugins with colliding priorities have now deterministic sorting based on their name
  [#8957](https://github.com/Kong/kong/pull/8957)
- External Plugins: better handling of the logging when a plugin instance loses the instances_id in an event handler
  [#8652](https://github.com/Kong/kong/pull/8652)
- **ACME**: `auth_method` default value is set to `token`
  [#8565](https://github.com/Kong/kong/pull/8565)
- **ACME**: Added cache for `domains_matcher`
  [#9048](https://github.com/Kong/kong/pull/9048)
- **syslog**: `conf.facility` default value is now set to `user`
  [#8564](https://github.com/Kong/kong/pull/8564)
- **AWS-Lambda**: Removed `proxy_scheme` field from schema
  [#8566](https://github.com/Kong/kong/pull/8566)
- **AWS-Lambda**: Change path from request_uri to upstream_uri, fix uri can not follow the rule defined in the request-transformer configuration
  [#9058](https://github.com/Kong/kong/pull/9058) [#9129](https://github.com/Kong/kong/pull/9129)
- **hmac-auth**: Removed deprecated signature format using `ngx.var.uri`
  [#8558](https://github.com/Kong/kong/pull/8558)
- Remove deprecated `blacklist`/`whitelist` config fields from bot-detection, ip-restriction and ACL plugins.
  [#8560](https://github.com/Kong/kong/pull/8560)
- **Zipkin**: Correct the balancer spans' duration to include the connection time
  from Nginx to the upstream.
  [#8848](https://github.com/Kong/kong/pull/8848)
- **Zipkin**: Correct the calculation of the header filter start time
  [#9230](https://github.com/Kong/kong/pull/9230)
- **Zipkin**: Compatibility with the latest Jaeger header spec, which makes `parent_id` optional
  [#8352](https://github.com/Kong/kong/pull/8352)
- **LDAP-Auth**: Refactored ASN.1 parser using OpenSSL API through FFI.
  [#8663](https://github.com/Kong/kong/pull/8663)
- **Rate-Limiting** and **Response-ratelimiting**: Fix a disordered behaviour caused by `pairs` function
  which may cause Postgres DEADLOCK problem [#8968](https://github.com/Kong/kong/pull/8968)
- **Response-rate-Limiting**: Fix a disordered behaviour caused by `pairs` function
  which may cause Postgres DEADLOCK problem [#8968](https://github.com/Kong/kong/pull/8968)
- **gRPC gateway**: Fix the handling of boolean fields from URI arguments
  [#9180](https://github.com/Kong/kong/pull/9180)
- **Serverless Functions**: Fix problem that could result in a crash
  [#9269](https://github.com/Kong/kong/pull/9269)
- **Azure-functions**: Support working without dummy service
  [#9177](https://github.com/Kong/kong/pull/9177)


#### Clustering

- The cluster listener now uses the value of `admin_error_log` for its log file
  instead of `proxy_error_log` [#8583](https://github.com/Kong/kong/pull/8583)
- Fixed a typo in some business logic that checks the Kong role before setting a
  value in cache at startup [#9060](https://github.com/Kong/kong/pull/9060)
- Fixed DP get zero size config while service with plugin-enabled route is disabled
  [#8816](https://github.com/Kong/kong/pull/8816)
- Localize `config_version` to avoid a race condition from the new yielding config loading code
  [#8188](https://github.com/Kong/kong/pull/8818)

#### PDK

- `kong.response.get_source()` now return an error instead of an exit when plugin throws
  runtime exception on access phase [#8599](https://github.com/Kong/kong/pull/8599)
- `kong.tools.uri.normalize()` now does escaping of reserved and unreserved characters more correctly
  [#8140](https://github.com/Kong/kong/pull/8140)

## Previous releases

Please see [CHANGELOG-OLD.md](CHANGELOG-OLD.md) file for < 3.0 releases.

[Back to TOC](#table-of-contents)

[3.3.0]: https://github.com/Kong/kong/compare/3.2.0...3.3.0
[3.2.0]: https://github.com/Kong/kong/compare/3.1.0...3.2.0
[3.1.0]: https://github.com/Kong/kong/compare/3.0.1...3.1.0
[3.0.1]: https://github.com/Kong/kong/compare/3.0.0...3.0.1
[3.0.0]: https://github.com/Kong/kong/compare/2.8.1...3.0.0
