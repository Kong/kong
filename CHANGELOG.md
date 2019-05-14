## 0.4 13-May-2019

### Changed

- Change schema to a new DAO format
- Use pdk

## 0.3.0 30-Nov-2018

### Added

- Add a new configuration `config.upstream_fallback` which causes the plugin to
not apply the canary upstream if it's marked as unhealthy by Kong's
healthchecker

## 0.2.1 26-Jul-2018

### Fixed

- Fixed `type` attribute for port configuration setting

## 0.2.0 1-Jun-2018

### Added

- Added whitelist and blacklist options to be able to select consumers instead
  of having random consumers.
- Added the port parameter to be able to be set a new port for the alternate
  upstream.

## 0.1.0

### Added

- First commit for Kong plugin to handle Canary release of Kong APIs
  to new upstream host or URIs.

