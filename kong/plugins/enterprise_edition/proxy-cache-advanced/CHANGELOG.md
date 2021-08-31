## 0.5.6

- remove empty migration

## 0.5.5

- chore(*) add copyright
- fix(test) remove C* 2.2 test

## 0.5.4

- Fix cache usage when url includes empty query string param

## 0.5.3

- chore(*) use each_by_name instead of select_all (#83)
- tests(invalidations) ensure we consume body before re-running wait_until callback

## 0.5.2

### Fixed

- fix vitals into the log phase

## 0.5.1

### Changed

- improved performance by not inheriting from the BasePlugin class
- convert the plugin away from deprecated functions

### Fixed

- Allow nginx to proxy requests in front of Kong

## 0.5.0

### Changed

- plugin renamed to proxy-cache-advanced

### Added

- `config.bypass_on_err` bypasses cache when strategy fails

## 0.4.2

### Fixed

- kong can be started with proxy-cache plugin and stream_listen directive

## 0.4.1

### Added

- Add unit tests to see if the schema accepts a `redis.cluster_addresses`
  parameter

## 0.4

### Changed

- Convert to new dao
- Use pdk
- Change default shared dictionary name to `kong_db_cache`

## 0.3.6

### Fixed

- Allow caching of responses without an explicit `public` directive in the
  `Cache-Control` header
- Correct an issue where the value of the `Expires` header would always be
  reported as `nil`

### Added

- Add `application/json` to config `content-type`

## 0.3.5

### Fixed

- Fix an issue where the same cache key would be generated for different APIs
  if they were accessed by the same consumer

### Added

- Support for Routes and Services: previously to this version, access to
  different routes would result in the same cache key

## 0.3.4

### Changed

- Dropped migrations which register entity with Resource table as Kong-ee
  0.33 will not have that table in favor of new RBAC implementaion.

## 0.3.3

### Fixed

- Avoid shortcircuiting subsequent plugins by using `responses.send`
instead of `ngx.exit`
- Fix issue where a 500 would be returned in PATCH requests
- Fix issue where Proxy Cache would overwrite `X-RateLimit-Remaining` headers

### Added

- Expose request and response bodies in the Nginx request context to
allow access by logging plugins

## 0.3.2

### Fixed

- Perform the same after_access hooks as core, so that requests that are
short-circuited still take part in other EE processing (like counting number
of requests)

## 0.3.1

### Fixed

- Update RBAC module path based on upstream development.

## 0.3.0

### Added

- Support for Redis as a backing store to hold cache data. Both standalone
  Redis and Redis sentinel are supported.

### Fixed

- Cast `response_code` values to an integer array to better interact with
  Kong's API.

## 0.2.1

### Fixed

- `response_code` can be omitted, but cannot be an empty string.
- `response_code` schema fix: response_code is required to be an integer
or convertible to an integer, otherwise a `400 Bad Request` is returned.

## 0.2.0

### Added

- Implement partial support for Cache-Control directives.
- Introduce `storage_ttl` configuration directive.
- Store the length of the response body in cache metadata.
- Added simpler Admin API endpoint to list/flush cache entities.
- Propagate cache purges cluster-wide for plugin instances that use
  a node-local cache strategy (e.g., the `memory` strategy).
- Send the `X-Kong-Proxy-Latency` and `X-Kong-Upstream-Latency` headers
  in the downstream response when serving from cache.

### Fixed

- Respect configured cacheable request methods.

## 0.1.0

### Added

- Initial feature set.
