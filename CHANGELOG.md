## v1.0.1 (Upcoming)

### Fixed

- Fix IMPORTANT! verify expiry and scopes checks on jwt tokens
- Fix finding consumer by custom id
- Fix runtime error on unexpected function, kong.log.error -> kong.log.err


## v1.0.0

### Changed

- Kong 1.0 CE / EE 0.35 Support (drops support for older releases)
- Change function `unauthorized` log level from notice to debug

## v0.1.1

### Changed

- Change `config.access_token_upstream_header` default value from `Authorization` to `Authorization:Bearer`
- Change now you can suffix the `config.access|channel_token_request_header` and
  `config.access|channel_token_upstream_header` with `:Bearer` or `:Basic` (case-insensitive).
  For request headers it just means that we look from the header without the suffix,
  but for the upstream headers it means that you can force the prefix
 
## v0.1.0

### Added

- Add `config.enable_instrumentation`
- Add `config.access_token_introspection_timeout`
- Add `config.channel_token_introspection_timeout`

### Changed

- Change `config.access_token_request_header` default value from `authorization:bearer` to `Authorization`
- Change `config.access_token_upstream_header` default value from `authorization:bearer` to `Authorization`
- Change both access token and channel token headers may be prefixed with `"Bearer"` or `"Basic"` (case-insensitive)

## v0.0.9

### Changed

- Change in plugins Admin API to make it more stable on invalid keysets

### Added

- Add `config.enable_access_token_introspection`
- Add `config.enable_channel_token_introspection`
- Add better error logging on plugin configuration phase

## v0.0.8

### Changed

- Change the checking of tokens to be ordered: `access token`, `channel token`
- Change the priority of the plugin from `850` to `999`
- Change `no_consumer` from `false` to `true`
- Rename `config.access_token_introspection_claim` to `config.access_token_introspection_jwt_claim` 
- Rename `config.channel_token_introspection_claim` to `config.channel_token_introspection_jwt_claim`

### Added

- Add `config.access_token_optional`
- Add `config.channel_token_optional`
- Add `config.trust_access_token_introspection`
- Add `config.trust_channel_token_introspection`
- Add `config.access_token_consumer_claim`
- Add `config.channel_token_consumer_claim`
- Add `config.access_token_consumer_by`
- Add `config.channel_token_consumer_by`
- Add `config.access_token_introspection_consumer_claim`
- Add `config.channel_token_introspection_consumer_claim`
- Add `config.access_token_introspection_consumer_by`
- Add `config.channel_token_introspection_consumer_by`

## v0.0.7

### Fixed

- Fix typo in `access_token_intrspection_scopes_required` (the missing `o`)

## v0.0.6

### Added

- Add `config.access_token_introspection_leeway`
- Add `config.access_token_introspection_scopes_required`
- Add `config.access_token_introspection_scopes_claim`
- Add `config.verify_access_token_introspection_expiry`
- Add `config.verify_access_token_introspection_scopes`
- Add `config.channel_token_introspection_leeway`
- Add `config.channel_token_introspection_scopes_required`
- Add `config.channel_token_introspection_scopes_claim`
- Add `config.verify_channel_token_introspection_expiry`
- Add `config.verify_channel_token_introspection_scopes`

## v0.0.5

### Added

- Add `config.access_token_introspection_body_args`
- Add `config.channel_token_introspection_body_args`

## v0.0.4

### Added

- Add documentation
- Add `config.access_token_keyset`
- Add `config.channel_token_keyset`
- Add `config.cache_access_token_introspection`
- Add `config.cache_channel_token_introspection`

### Changed

- Change `config.access_token_introspection_claim` to support nested claims (similar to `config.access_token_scopes_claim`).
- Change `config.channel_token_introspection_claim` to support nested claims (similar to `config.channel_token_scopes_claim`).

## v0.0.3

### Changed

- Plugin renamed to `jwt-signer`, also affects the Github repository as well.

## v0.0.2

### Fixed

- Fix jwks.updated_at to correctly update on key rotation.

## v0.0.1

### Added

- Initial release.

