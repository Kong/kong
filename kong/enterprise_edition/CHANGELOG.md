## 0.30 (Unreleased) - 2018/01/10

### Changed

- Vitals
  - Minutes data is now aggregated at the same time as seconds
  - **Breaking Changes**
    - Previous Vitals API (part of the Admin API) is replaced with a new, better one. Not backwards compatible
    - Upgrading from Kong EE (0.29) will result in the loss of previous Vitals data.

### Added

- Vitals
  - Addition of **"node-specific"** dimension for previously-released metrics: Proxy Latency (Request) and Datastore (L2) Cache
  - New metrics and dimenions:
    - **Request Count per Consumer**, by Node or Cluster
    - **Total Request Count**, by Node or Cluster
    - **Upstream Latency** (the time between a request being sent upstream by Kong, and the response being received by Kong), by Node or Cluster
    - All new metrics and dimensions accessible in Admin GUI and API
  - **Important limitations and notifications:**  Postgres 9.5+ only - no Cassandra support yet

### Fixed

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
