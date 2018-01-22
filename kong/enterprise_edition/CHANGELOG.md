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
