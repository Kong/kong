## 1.0.0

### Changed

* Moved old schema to new schema format
* Use pdk

## 0.0.6

### Fixes

* Ensure that the configured `proxy_port` is forwarded in the upstream
  request's URL. This fixues issues when using non-default ports for
  HTTP/HTTPs
* Fix an issue preventing the plugin from working with requests using chunked
  TE

**Note:** This release is set to be compatible with Kong Enterprise 0.34-1
only, and as such, does not support the new DAO/Schema/PDK, or other new
features of Kong 1.0.

## 0.0.5

### Fixes

* Fix an issue leading the plugin to perform an unnecessary DNS query in the access phase

## 0.0.4

### Added

* HTTPS support: the plugin can now make CONNECT request to proxy
to start SSL(HTTPS) communication with remote host

## 0.0.3

### Fixes

* Fix Kong core dependency causing the `access` phase handle to fail

## 0.0.2

* Add support for delayed response
* Add `Via` header
