## 0.4.4

- Support for gzipped content
- Support for manipulating arrays and nested JSON

## 0.4.3

- Add copyright headers

## 0.4.2

### Fixed

- Added missing `json_types` configuration field for `add`, `replace` and `append` operations.

## 0.4.1

### Fixed

- Fix migration that changed `whitelist` to `allow`.

## 0.4.0

### Added

- Added support to specify JSON types for configuration values. For example, by doing `config.add.json_types: ["number"]`, the plugin will convert the "-1" into -1.
- Improved performance by not inheriting from the BasePlugin class
- The plugin is now defensive against possible errors and nil header values

### Fixed

- Preserve empty arrays correctly
- Prevent the plugin from throwing an error when its access handler did not get a chance to run (e.g. on short-circuited, unauthorized requests)
- Standardize on `allow` instead of `whitelist` to specify the parameters name which should be allowed in response JSON body

## 0.3.3

### Added

- Rename option for header in config.rename.headers

## 0.3.2

### Added

- Added support for removal of specific header including with regex

## 0.3.1

### Fixed

- Fixed a bug where the plugin was returning an empty body in the response for status codes outside of those specified in `config.replace.if_status`. For example, if we specified a `config.replace.if_status=404` and a body `config.replace.body=test` and the status code was 200, the response would be empty.

## 0.3

### Added

- Support for filtering JSON body with new configration `config.whitelist.json`
added.

- Added a support of status code ranges for `if_status` configuration parameter.
Now you can provide status code ranges and single status codes together
(e.g., 201-204,401)

- Support arbitrary transforms through lua functions

## 0.2

### Added

- Added a support of status code ranges for `if_status` configuration parameter.
Now you can provide status code ranges and single status codes together
(e.g., 201-204,401)

### Changed

- Change to use new dao

## 0.1.0

### Added

- This is a fork of Kong's [response-transformer][response-transformer-plugin]
plugin with the following additions:
  * Conditional transformations: each transformation type (i.e., replace, remove,
  add, append) can be conditionally applied, depending on the response status -
  fulfilling use cases like "remove the response body if the response code is
  500". The `if_status` configuration item , which is part of each transform type
  (e.g., `replace.if_status`), controls this behavior
  * Introduced an option to replace the entire body of a response, as opposed to
  only a specific JSON field. This allows for replacing the response body with
  arbitrary data. The configuration item `replace.body` controls this behavior


---
[response-transformer-plugin]: https://docs.konghq.com/hub/kong-inc/response-transformer/
