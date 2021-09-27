## 0.38.0

- Keep the configured name case on append/add headers.
  Fixes [#28](https://github.com/Kong/kong-plugin-request-transformer/issues/28)
- Include the `type` function in template environment.
  Because headers may contain array elements such as duplicated headers,
  `type` is a useful function in these cases.
- Fix the construction of the error message when a template throws a Lua error.
  [#25](https://github.com/Kong/kong-plugin-request-transformer/issues/25)

## 0.37.4

- chore(*) add copyright

## 0.37.3

### Changed

* Standardize on `allow` instead of `whitelist` to specify the parameter names that should be allowed in request JSON body. Previous `whitelist` nomenclature is deprecated and support will be removed in Kong 3.0.

## 0.37.2

### Changed

* properly throw template errors

### Added

* Pongo based CI

## 0.37.1

### Changed

* Improved performance by not inheriting from the BasePlugin class
* Convert the plugin away from deprecated functions

### Fixed

* Fixed bug on adding a header with the same name as a removed one

## 0.37.0

- added: Support for filtering JSON body with new configration `config.whitelist.body`
added.

## 0.35.2

- added: render values from kong.ctx.shared

## 0.35.1

### Fixed

- Correct logic error when determining whether to transform querystring
- Fix a bug where the code does not allow adding and appending a body
parameter if there is no body in the POST request
- Change the priorities for the transformations to allow the
headers to be transformed before the body

## 0.35

### Changed

- Convert to new dao

## 0.34.0

### Changed
 - Internal improvements

## 0.1.0

- `pre-function` and `post-function` enterprise plugins added
