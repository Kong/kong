## Kong


### Performance
#### Performance

- Speeded up the router matching when the `router_flavor` is `traditional_compatible` or `expressions`.
 [#12467](https://github.com/Kong/kong/issues/12467)
 [KAG-3653](https://konghq.atlassian.net/browse/KAG-3653)
#### Plugin

- **Opentelemetry**: increase queue max batch size to 200
 [#12488](https://github.com/Kong/kong/issues/12488)
 [KAG-3173](https://konghq.atlassian.net/browse/KAG-3173)



### Dependencies
#### Core

- Bumped lua-kong-nginx-module from 0.8.0 to 0.9.1
 [#12752](https://github.com/Kong/kong/issues/12752)
 [KAG-4050](https://konghq.atlassian.net/browse/KAG-4050)

- Bumped lua-resty-openssl to 1.2.1
 [#12665](https://github.com/Kong/kong/issues/12665)


- Bumped lua-resty-timer-ng to 0.2.7
 [#12756](https://github.com/Kong/kong/issues/12756)
 [KAG-3653](https://konghq.atlassian.net/browse/KAG-3653)

- Bumped PCRE from the legacy libpcre 8.45 to libpcre2 10.43
 [#12366](https://github.com/Kong/kong/issues/12366)
 [KAG-3571](https://konghq.atlassian.net/browse/KAG-3571) [KAG-3521](https://konghq.atlassian.net/browse/KAG-3521) [KAG-2025](https://konghq.atlassian.net/browse/KAG-2025)
#### Default

- Add package `tzdata` to DEB Docker image for convenient timezone setting.
 [#12609](https://github.com/Kong/kong/issues/12609)
 [FTI-5698](https://konghq.atlassian.net/browse/FTI-5698)

- Bumped LuaRocks from 3.9.2 to 3.11.0
 [#12662](https://github.com/Kong/kong/issues/12662)
 [KAG-3883](https://konghq.atlassian.net/browse/KAG-3883)

### Features
#### Configuration

- now TLSv1.1 and lower is by default disabled in OpenSSL 3.x
 [#12420](https://github.com/Kong/kong/issues/12420)
 [KAG-3259](https://konghq.atlassian.net/browse/KAG-3259)

- **Schema**: Added a deprecation field attribute to identify deprecated fields
 [#12686](https://github.com/Kong/kong/issues/12686)
 [KAG-3915](https://konghq.atlassian.net/browse/KAG-3915)
#### PDK

- Add `latencies.receive` property to log serializer
 [#12730](https://github.com/Kong/kong/issues/12730)
 [KAG-3798](https://konghq.atlassian.net/browse/KAG-3798)
#### Plugin

- Addded support for EdDSA algorithms in JWT plugin
 [#12726](https://github.com/Kong/kong/issues/12726)


- Addded support for ES512, PS256, PS384, PS512 algorithms in JWT plugin
 [#12638](https://github.com/Kong/kong/issues/12638)
 [KAG-3821](https://konghq.atlassian.net/browse/KAG-3821)

### Fixes
#### Configuration

- Fixed default value in kong.conf.default documentation from 1000 to 10000
for upstream_keepalive_max_requests option.
 [#12643](https://github.com/Kong/kong/issues/12643)
 [KAG-3360](https://konghq.atlassian.net/browse/KAG-3360)

- Fix an issue where an external plugin (Go, Javascript, or Python) would fail to
apply a change to the plugin config via the Admin API.
 [#12718](https://github.com/Kong/kong/issues/12718)
 [KAG-3949](https://konghq.atlassian.net/browse/KAG-3949)

- Set security level of gRPC's TLS to 0 when ssl_cipher_suite is set to old
 [#12613](https://github.com/Kong/kong/issues/12613)
 [KAG-3259](https://konghq.atlassian.net/browse/KAG-3259)
#### Core

- **DNS Client**: Ignore a non-positive values on resolv.conf for options timeout, and use a default value of 2 seconds instead.
 [#12640](https://github.com/Kong/kong/issues/12640)
 [FTI-5791](https://konghq.atlassian.net/browse/FTI-5791)

- update file permission of kong.logrotate to 644
 [#12629](https://github.com/Kong/kong/issues/12629)
 [FTI-5756](https://konghq.atlassian.net/browse/FTI-5756)

- Fix the missing router section for the output of the request-debugging
 [#12234](https://github.com/Kong/kong/issues/12234)
 [KAG-3438](https://konghq.atlassian.net/browse/KAG-3438)

- Fixed an issue where router may not work correctly
when the routes configuration changed.
 [#12654](https://github.com/Kong/kong/issues/12654)
 [KAG-3857](https://konghq.atlassian.net/browse/KAG-3857)

- Fixed an issue where SNI-based routing does not work
using tls_passthrough and the traditional_compatible router flavor
 [#12681](https://github.com/Kong/kong/issues/12681)
 [KAG-3922](https://konghq.atlassian.net/browse/KAG-3922) [FTI-5781](https://konghq.atlassian.net/browse/FTI-5781)

- fix vault initialization by postponing vault reference resolving on init_worker
 [#12554](https://github.com/Kong/kong/issues/12554)
 [KAG-2907](https://konghq.atlassian.net/browse/KAG-2907)

- **Vault**: do not use incorrect (default) workspace identifier when retrieving vault entity by prefix
 [#12572](https://github.com/Kong/kong/issues/12572)
 [FTI-5762](https://konghq.atlassian.net/browse/FTI-5762)

- Use `-1` as the worker ID of privileged agent to avoid access issues.
 [#12385](https://github.com/Kong/kong/issues/12385)
 [FTI-5707](https://konghq.atlassian.net/browse/FTI-5707)

- **Plugin Server**: fix an issue where Kong fails to properly restart MessagePack-based pluginservers (used in Python and Javascript plugins, for example)
 [#12582](https://github.com/Kong/kong/issues/12582)
 [KAG-3765](https://konghq.atlassian.net/browse/KAG-3765)

- revert the hard-coded limitation of the ngx.read_body() API in OpenResty upstreams' new versions when downstream connections are in HTTP/2 or HTTP/3 stream modes.
 [#12658](https://github.com/Kong/kong/issues/12658)
 [FTI-5766](https://konghq.atlassian.net/browse/FTI-5766) [FTI-5795](https://konghq.atlassian.net/browse/FTI-5795)

- Each Kong cache instance now utilizes its own cluster event channel. This approach isolates cache invalidation events and reducing the generation of unnecessary worker events.
 [#12321](https://github.com/Kong/kong/issues/12321)
 [FTI-5559](https://konghq.atlassian.net/browse/FTI-5559)
#### Plugin

- **Jwt**: fix an issue where the plugin would fail when using invalid public keys for ES384 and ES512 algorithms.
 [#12724](https://github.com/Kong/kong/issues/12724)


- Add WWW-Authenticate headers to all 401 response in key auth plugin.
 [#11794](https://github.com/Kong/kong/issues/11794)
 [KAG-321](https://konghq.atlassian.net/browse/KAG-321)

- **Opentelemetry**: fix otel sampling mode lua panic bug when http_response_header_for_traceid option enable
 [#12544](https://github.com/Kong/kong/issues/12544)
 [FTI-5742](https://konghq.atlassian.net/browse/FTI-5742)
#### Admin API

- **Admin API**: fixed an issue where calling the endpoint `POST /schemas/vaults/validate` was conflicting with the endpoint `/schemas/vaults/:name` which only has GET implemented, hence resulting in a 405.
 [#12607](https://github.com/Kong/kong/issues/12607)
 [KAG-3699](https://konghq.atlassian.net/browse/KAG-3699)
#### Default

- Fix a bug where the ulimit setting (open files) is low Kong will fail to start as the lua-resty-timer-ng exhausts the available worker_connections. Decrease the concurrency range of the lua-resty-timer-ng library from [512, 2048] to [256, 1024] to fix this bug.
 [#12606](https://github.com/Kong/kong/issues/12606)
 [KAG-3779](https://konghq.atlassian.net/browse/KAG-3779) [FTI-5780](https://konghq.atlassian.net/browse/FTI-5780)

- Fix an issue where external plugins using the protobuf-based protocol would fail to call the `kong.Service.SetUpstream` method with an error `bad argument #2 to 'encode' (table expected, got boolean)`.
 [#12727](https://github.com/Kong/kong/issues/12727)

