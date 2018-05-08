## 0.32 - 2018/05/22

### Notifications

- **Kong EE 0.32** inherits from **Kong CE 0.13.1** - hence, 0.13.0; make sure to read their changelogs:
  - [0.13.0 Changelog](https://github.com/Kong/kong/blob/master/CHANGELOG.md#0130---20180322)
  - [0.13.1 Changelog](https://github.com/Kong/kong/blob/master/CHANGELOG.md#0131---20180423)
- **Kong EE 0.32** has these notices from **Kong CE 0.13**:
  - Support for **Postgres 9.4 has been deprecated, but Kong will still start** - versions beyond 0.32 will not start with Postgres 9.4 or prior
  - Support for **Cassandra 2.1 has been deprecated, but Kong will still start** - versions beyond 0.32 will not start with Cassandra 2.1 or prior
  - Additional requirements:
    - **Vitals** requires Postgres 9.5+
    - **Dev Portal** requires Cassandra 3.0+
  - Galileo plugin is deprecated and will reach EOL soon
- **Breaking**: The `latest` tag in Kong Enterprise Docker repository changed from CentOS to Alpine - which might result in breakage if additional packages are assumed to be in the image, as the Alpine image only contains a minimal set of packages installed
- **OpenID Connect**
  - The plugins listed below were deprecated in favor of the all-in-one openid-connect plugin:
    - `openid-connect-authentication`
    - `openid-connect-protection`
    - `openid-connect-verification`

### Changes

- **New Data Model** - Kong EE 0.32 is the first Enterprise version including the **new model**, released with Kong CE 0.13
- **Rate Limiting Advanced**
  - **Breaking** - Enterprise Rate Limiting, named `rate-limiting` up to EE 0.31, was renamed `rate-limiting-advanced` and CE Rate Limiting was imported as `rate-limiting`
  - Rate Limiting Advanced, similarly to CE rate-limiting, now uses a dedicated shared dictionary named `kong_rate_limiting_counters` for its counters; if you are using a custom template, make sure to define the following shared memory zones:
  ```
  lua_shared_dict kong_rate_limiting_counters 12m;
  ```
- **Vitals**
  - Vitals uses two dedicated shared dictionaries. If you use a custom template, define the following shared memory zones for Vitals:
  ```
  lua_shared_dict kong_vitals_counters 50m;
  lua_shared_dict kong_vitals_lists     1m;
  ```
  You can remove any existing shared dictionaries that begin with `kong_vitals_`, e.g., `kong_vitals_requests_consumers`
- **OpenID Connect**
  - Remove multipart parsing of ID tokens - they were not proxy safe
  - Change `self_check` to run only on content and access phases
  - Change expired or non-active access tokens to give `401` instead of `403`

### Features

- **Admin GUI**
  - New Listeners (Admin GUI + Developer Portal)
  - Routes and Services GUI
  - New Plugins thumbnail view
  - Healthchecks GUI
  - Syntax for form-encoded array elements
- **Vitals**
  - **Status Code** tracking - GUI and API
    - Status Code groups per Cluster - counts of `1xx`, `2xx`, `3xx`, `4xx`, `5xx` groups across the cluster over time. Visible in the Admin GUI at `ADMIN_URL/vitals/status-codes`
    - Status Codes per Service - count of individual status codes correlated to a particular service. Visible in the Admin GUI at `ADMIN_URL/services/{service_id}`
    - Status Codes per Route - count of individual status codes correlated to a particular route. Visible in the Admin GUI at `ADMIN_URL/routes/{route_id}`
    - Status Codes per Consumer and Route - count of individual status codes returned to a given consumer on a given route.  Visible in the Admin GUI at `ADMIN_URL/consumers/{consumer_id}`
- **Dev Portal**
  - Code Snippets
  - Developer "request access" full life-cycle
  - Default Dev Portal included in Kong disto (with default theme)
  - Authentication on Dev Portal out of box (uncomment in Kong.conf)
  - Docs for Routes/Services for Dev Portal
  - Docs for Admin API
  - **Requires Migration** - `/files` endpoint is now protected by RBAC
- **Plugins**
  - **Rate Limiting Advanced**: add a `dictionary_name` configuration, to allow using a custom dictionary for storing counters
  - **Requires Migration - Rate Limiting CE** is now included in EE
  - **Request Transformer CE** is now included in EE
  - **Edge Compute**: plugin-based, Lua-only preview
  - **Proxy Cache**: Customize the cache key, selecting specific headers or query params to be included
  - **Opentracing Plugin**: Kong now adds detailed spans to Zipkin and Jaeger distributed tracing tools
  - **Azure Plugin**: Invoke Azure functions from Kong
  - **LDAP Advanced**: LDAP plugin with augmented ability to search by LDAP fields
- **OpenID Connect**
  - Bearer token is now looked up on `Access-Token` and `X-Access-Token` headers in addition to Authorization Bearer header (query and body args are supported as before)
  - JWKs are rediscovered and the new keys are cached cluster wide (works better with keys rotation schemes)
  - Admin API does self-check for discovery endpoint when the plugin is added and reports possible errors back
  - Add configuration directives
    - `config.extra_jwks_uris`
    - `config.credential_claim`
    - `config.session_storage`
    - `config.session_memcache_prefix`
    - `config.session_memcache_socket`
    - `config.session_memcache_host`
    - `config.session_memcache_port`
    - `config.session_redis_prefix`
    - `config.session_redis_socket`
    - `config.session_redis_host`
    - `config.session_redis_port`
    - `config.session_redis_auth`
    - `config.session_cookie_lifetime`
    - `config.authorization_cookie_lifetime`
    - `config.forbidden_destroy_session`
    - `config.forbidden_redirect_uri`
    - `config.unauthorized_redirect_uri`
    - `config.unexpected_redirect_uri`
    - `config.scopes_required`
    - `config.scopes_claim`
    - `config.audience_required`
    - `config.audience_claim`
    - `config.discovery_headers_names`
    - `config.discovery_headers_values`
    - `config.introspect_jwt_tokens`
    - `config.introspection_hint`
    - `config.introspection_headers_names`
    - `config.introspection_headers_values`
    - `config.token_exchange_endpoint`
    - `config.cache_token_exchange`
    - `config.bearer_token_param_type`
    - `config.client_credentials_param_type`
    - `config.password_param_type`
    - `config.hide_credentials`
    - `config.cache_ttl`
    - `config.run_on_preflight`
    - `config.upstream_headers_claims`
    - `config.upstream_headers_names`
    - `config.downstream_headers_claims`
    - `config.downstream_headers_names`

### Fixes

- **Core**
  - **Healthchecks**
    - Fix an issue where updates made through `/health` or `/unhealth` wouldn't be propagated to other Kong nodes
    - Fix internal management of healthcheck counters, which corrects detection of state flapping
  - **DNS**: a number of fixes and improvements were made to Kong's DNS client library, including:
    - The ring-balancer now supports `targets` resolving to an SRV record without port information (`port=0`)
    - IPv6 nameservers with a scope in their address (eg. `nameserver fe80::1%wlan0`) will now be skipped instead of throwing errors
- **Rate Limiting Advanced**
  - Fix `failed to upsert counters` error
  - Fix issue where an attempt to acquire a lock would result in an error
  - Mitigate issue where lock acquisitions would lead to RL counters being lost
- **Proxy Cache**
  - Fix issue where proxy-cache would shortcircuit requests that resulted in a cache hit, not allowing subsequent plugins - e.g., logging plugins - to run
  - Fix issue where PATCH requests would result in a 500 response
  - Fix issue where Proxy Cache would overwrite X-RateLimit headers
- **Request Transformer**
  - Fix issue leading to an Internal Server Error in cases where the Rate Limiting plugin returned a 429 Too Many Requests response
- **AWS Lambda**
  - Fix issue where an empty array `[]` was returned as an empty object `{}`
- **Galileo**
  - Fix issue that prevented Galileo from reporting requests that were cached by proxy-cache
  - Fix issue that prevented Galileo from showing request/response bodies of requests served by proxy-cache
- **OpenID Connect**
  - Fix `exp` retrieval
  - Fix `jwt_session_cookie` verification
  - Fix consumer mapping using introspection
  - Fix set headers when callback to get header value failed
  - Fix config.scopes when set to null or `""` so that it doesn't add openid scope forcibly

## 0.31 - 2018/03/13

### Changed

- Galileo plugin is disabled by default in this version, needing to be explicitly enabled via the custom_plugins configuration
  - NOTE: If a user had the Galileo plugin applied in an older version and migrate to 0.31, Kong will fail to restart unless the user enables it via the custom_plugins configuration; however, it is still possible to enable the plugin per API or globally without adding it to custom_plugins
- OpenID Connect plugin:
  - Change config.client_secret from required to optional
  - Change config.client_id from required to optional
  - If anonymous consumer is not found Internal Server Error is returned instead of Forbidden
  - Breaking Change - config.anonymous now behaves similarly to other plugins and doesn't halt execution or proxying (previously it was used just as a fallback for consumer mapping) and the plugin always needed valid credentials to be allowed to proxy if the client wasn't already authenticated by higher priority auth plugin
  - Anonymous consumer now uses a simple cache key that is used in other plugins
In case of auth plugins concatenation, the OpenID Connect plugin now removes remnants of anonymous

### Added

- Admin GUI
  - Add notification bar alerting users that their license is about to expire, and has expired.
  - Add new design to vitals overview, table breakdown, and a new tabbed chart interface.
  - Add top-level vitals section to the sidebar.
- Requires migration - Vitals
  - New datastore support: Cassandra 2.1+
  - Support for averages for Proxy Request Latency and Upstream Latency
- Requires migration - Dev Portal
  - Not-production-ready feature preview of:
   - "Public only" Portal - no authentication (eg. the portal is fully accessible to anyone who can access it)
   - Authenticated Portal - Developers must log in, and then they can see what they are entitled to see

### Fixed

- Admin GUI
  - Remove deprecated orderlist field from Admin GUI Upstreams entity settings
  - Fix issue where Admin GUI would break when running Kong in a custom prefix
  - Fix issue where Healthchecks had a field typed as number instead of string.
  - Fix issue where Healthchecks form had incorrect default values.
  - Fix issue where table row text was overflowing and expanding the page.
  - Fix issue where notification bar in mobile view could have text overflow beyond the container.
  - Fix issue where deleting multiple entities in a list would cause the delete modal to not show.
  - Fix issue where cards on the dashboard were not evenly sized and spaced.
  - Fix issue where cards on the dashboard in certain widths could have text overflow beyond their container.
  - Fix issue where Array's on Plugin Entities were not being processed and sent to the Admin API.
  - Fix issue where Models were improperly handled when not updated and not sending default values properly.
  - Fix issue where Plugin lists were not displaying config object.
  - Fix issue where Kong was not processing SSL configuration for Admin GUI
- OpenID Connect plugin:
  - Fixed anonymous consumer mapping
- Vitals
  - Correct the stats returned in the "metadata" attribute of the /vitals/consumers/:consumer_id/* endpoints
  - Correct a problem where workers get out of sync when adding their data to cache
  - Correct inconsistencies in chart axes when toggling between views or when Kong has no traffic
- Proxy Cache
  - Fix issue that prevented cached requests from showing up in Vitals or Total Requests graphs
- Rate Limiting
  - Fix lock acquisition failure

## 0.30 - 2018/01/22

### Changed

- Rename of plugins
  - `request-transformer` becomes `request-transformer-advanced`
- Enterprise rate-limiting plugin
  - Change default `config.identifier` from ip to consumer
- Vitals
  - Aggregate minutes data at the same time as seconds data
  - **Breaking Changes**
    - Replace previous Vitals API (part of the Admin API) with new version. Not backwards compatible.
    - **Upgrading from Kong EE (0.29) will result in the loss of previous Vitals data**
- Admin GUI
  - Vitals chart settings stored in local storage
  - Improve vital chart legends
  - Change Make A Wish email to wish@konghq.com
- OpenID Connect plugins
  - Change config.login_redirect_uri from string to array
  - Add new configuration parameters
    - `config.authorization_query_args_client`
    - `config.client_arg`
    - `config.logout_redirect_uri`
    - `config.logout_query_arg`
    - `config.logout_post_arg`
    - `config.logout_uri_suffix`
    - `config.logout_methods`
    - `config.logout_revoke`
    - `config.revocation_endpoint`
    - `config.end_session_endpoint`
- OpenID Connect Library
  - Function `authorization:basic` now return as a third parameter, the grant type if one was found; previously, it returned parameter location in HTTP request
  - Issuer is no longer verified on discovery as some IdPs report different value (it is still verified with claims verification)

### Added

- New Canary Release plugin
- Vitals
  - Adds **"node-specific"** dimension for previously-released metrics: Proxy Latency (Request) and Datastore (L2) Cache
  - Adds new metrics and dimensions:
    - **Request Count per Consumer**, by Node or Cluster
    - **Total Request Count**, by Node or Cluster
    - **Upstream Latency** (the time between a request being sent upstream by Kong, and the response being received by Kong), by Node or Cluster
  - All new metrics and dimensions accessible in Admin GUI and API
  - **Important limitations and notifications:**  Postgres 9.5+ only - no Cassandra support yet
- Proxy Cache
  - Implement Redis (stand-alone and Sentinel) caching of proxy cache entities
- Rate Limiting
  - Provide fixed-window quota rate limiting (which is essentially what the CE rate-limiting plugin does) in addition to the current sliding window rate limiting
  - Add hide_client_headers configuration to disable response headers returned by the rate limiting plugin
- Admin GUI
  - Grouping support for Entity Forms
  - Hostname support for Vitals charts
  - Added consumer charts
  - Changed input type for certificates to text area
  - Added type inference
  - Add total requests and response latency charts
  - Add healthy / unhealthy buttons to Upstream Targets
  - Add vitals chart to dashboard
- OpenID Connect plugins
  - Support passing dynamic arguments to authorization endpoint from client
  - Support logout with optional revocation and RP-initiated logout

### Fixed

- Proxy Cache
  - Better handling of input configuration data types. In some cases configuration sent from the GUI would case requests to be bypassed when they should have been cached
- OAuth2 Introspection
  - Improved error handling in TCP/HTTP connections to the introspection server
- Vitals
  - Aggregating minutes at the same time as seconds are being written
  - Returning more than one minute's worth of seconds data
- Admin GUI
  - Input type for Certificates is now a text area box
  - Infer types based on default values and object type from the API Schema for Plugins

## 0.29 - 2017/11/14

### Changed

- Leverage Kong Community Edition 0.11.1 as the base for Kong Enterprise Edition.
- Implement a new versioning scheme for Kong Enterprise Edition
  (https://support.mashape.com/hc/en-us/articles/115002889713-Kong-Enterprise-Edition-Versioning).
- Clarify warning error messages in the Kong CLI utility upon encountering an
  error when attempting to interpolate the Admin GUI template file.
- Enable the OpenID Connect suite of plugins by default.

### Added

- Implement RBAC configuration functionality in the Admin GUI.
- Enterprise License File Validation
  - Implement license file validation as part of the Kong startup and lifecycle
    process (https://support.mashape.com/hc/en-us/articles/115003107454-Kong-Enterprise-Edition-Licensing).
  - Expose license file information via the `license` key of the root `/` Admin
    API endpoint response.
- Release the first iteration of Kong Vitals, storing and visualizing metrics
  related to Kong's in-memory caching and latency.
  (https://support.mashape.com/hc/en-us/articles/115002321753).
  - Vitals is initially available on **Postgres 9.5+ only** - Cassandra support will be added 
  in a future release of Kong EE.
  - **All functionality is subject to change in upcoming releases of Kong EE with no guaranteed 
  backward compatibility.** ** Vitals API will change completely in the next release, with zero 
  backward compatibility.
- Add the Forward Proxy plugin, allowing Kong to communicate to upstream services
  via a transparent HTTP proxy.
  (https://support.mashape.com/hc/en-us/articles/115002941293).
- OAuth2 Introspection:
  - Add support for the `anonymous` consumer configuration option.
  - Implement preflight bypass logic on `OPTIONS` requests.
- Proxy Cache:
  - Add limited support for Cache-Control directives.
  - Define a simpler Admin API interface to access and purge cache entities.
  - Propagate cache purges cluster-wide for plugin strategies that store cache
    data locally per node.
  - Send the X-Kong-Proxy-Latency and X-Kong-Upstream-Latency headers to the
    downstream client on cache hit.
  - Store the length of the response body in cache metadata.
  - Introduce the `storage_ttl` configuration directive.
- Rate-Limiting:
  - Treat the `namespace` config option as a fully optional configuration option.
- OpenID Connect:
  - Add `login_redirect_mode` configuration option.
 

### Fixed

- Handle a case in multipart form upload processing where large request bodies
  and sufficiently large `client_body_buffer_size` Nginx configuration options
  could lead to memory exhaustion in the Lua VM.
- Explicitly send HTTP response headers to disallow caching of Admin GUI assets.
- Properly display the `resource` attribute of RBAC permissions options in the
  Admin API.
- Proxy-Cache:
  - Implement stricter checking of the `response_code` configuration option.
  - Respect configured cacheable request methods.
- OpenID Connect:
  - Fix invalid re-verify to cleanup existing sessions.
