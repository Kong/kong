## 0.3.3

- Fix avoid manually utilising the plugins iterator

## 0.3.2

- fix plugin not running on latest 2.3 and 2.4
- exit functions running twice per response.

## 0.3.1

### Fixed

- plugin was not allowing access to `kong` module within the sandbox, only
to `kong.request`.


### Added

- CI testing using pongo.

## 0.3.0

### Changed

- Use kong sandbox functionality to run transform functions.

## 0.2.5

### Added

- Copyright headers.

## 0.2.4

### Fixed

- Get route from `ngx.ctx.route`, since `kong.router.get_route()` cannot be
called on the error phase.

## 0.2.3

### Changed

- Use route to detect an `unknown` exit instead of relying on a missing
workspace_id not being set. A request context with no route does not belong to
anything, so we use that for detecting `unknown`.

## 0.2.2

### Fixed

- hook into `kong.response.send` method. Some kong exit responses use
`kong.response.exit` and `kong.response.send`, so this fixes the plugin not
properly handling all exit responses.


## 0.2.1

### Added

- allow access to `kong` object on transformer functions.

### Changed

- remove `handle_admin`, it was a crazy idea.

## 0.2.0

### Added

- handle_* booleans to control what contexts the plugin can transform:

  * `handle_unknown`: exit responses on an unknown context (a request on an
  unexisting route belongs to no service, so it's "unknown").
  * `handle_unexpected`: unexpected exit responses, like a kong internal
  service error.
  * `handle_admin`: kong admin exit responses.

## 0.1.0

Initial release of exit-transformer. A plugin to customize kong exit responses
using lua code. It works by hooking into `kong.response.exit` method.
