## 0.32.2 - Unreleased

### Added

- Invalidation spec

### Fixed

- Fix issue where a request added a negative cache entry for an incorrect password attempt
- Fix issue where a 500 response would result when long passwords (> 128 chars) were being used

## 0.32.1

### Added

- Add fields
   * `consumer_by` - *optional*, default: { `username`, `custom_id` }
   * `consumer_optional` *optional* , default: `false`
     - By default, the consumer mapping is NOT optional. Set this config to
     `true` when you do not want the plugin to map to a kong consumer.

- Find consumers by `consumer_by` fields and map to ldap-auth user. This will
  set the authenticated consumer so that X-Consumer-{ID, USERNAME, CUSTOM_ID}
  headers are set and consumer functionality is available.

### Fixed

- Fix `require` statements pointing to CE ldap plugin
- Fix usage of LuaJIT ffi; `ffi.load` was being used to access an external
  symbol instead of `ffi.C.`

## 0.32.0

ldap-auth-advanced was forked from Kong CE ldap-auth.

### Added

### Fixed

### Changed

