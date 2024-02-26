## Kong


### Performance
#### Plugin

- **Opentelemetry**: increase queue max batch size to 200
 [#12488](https://github.com/Kong/kong/issues/12488)
 [KAG-3173](https://konghq.atlassian.net/browse/KAG-3173)



### Dependencies
#### Core

- Bumped PCRE from the legacy libpcre 8.45 to libpcre2 10.43
 [#12366](https://github.com/Kong/kong/issues/12366)
 [KAG-3571](https://konghq.atlassian.net/browse/KAG-3571) [KAG-3521](https://konghq.atlassian.net/browse/KAG-3521) [KAG-2025](https://konghq.atlassian.net/browse/KAG-2025)

### Features
#### Configuration

- now TLSv1.1 and lower is by default disabled in OpenSSL 3.x
 [#12420](https://github.com/Kong/kong/issues/12420)
 [KAG-3259](https://konghq.atlassian.net/browse/KAG-3259)

### Fixes
#### Configuration

- Set security level of gRPC's TLS to 0 when ssl_cipher_suite is set to old
 [#12613](https://github.com/Kong/kong/issues/12613)
 [KAG-3259](https://konghq.atlassian.net/browse/KAG-3259)
#### Core

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
#### Plugin

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
