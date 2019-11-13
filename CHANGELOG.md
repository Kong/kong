## 1.2.4

### Changed

- Remove the no-longer supported `run_on` field from plugin config schema

### Fixed

- None

## 1.2.3

### Changed

- Allow rendering values stored in `kong.ctx.shared` from the template renderer environment

### Fixed

- Fixed bug on adding a header with the same name as a removed one doesn't behave correctly

## 1.2.2

### Changed

- Remove leftover `print` call from schema validator

### Fixed

- Fix issue preventing JSON body transformation to be executed on empty body
upon Content-Type rewrite to `application/json`
  [#1](https://github.com/Kong/kong-plugin-request-transformer/issues/1)

## 1.2.1

### Changed

- Remove dependency to `BasePlugin` (not needed anymore)

## 0.35

### Changed

- Convert to new dao

## 0.34.0

### Changed
 - Internal improvements

## 0.1.0

- `pre-function` and `post-function` enterprise plugins added
