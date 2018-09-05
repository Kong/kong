## v0.0.7

- Fix typo in `access_token_intrspection_scopes_required` (the missing `o`)

## v0.0.6

- Add `access_token_introspection_leeway`
- Add `access_token_introspection_scopes_required`
- Add `access_token_introspection_scopes_claim`
- Add `verify_access_token_introspection_expiry`
- Add `verify_access_token_introspection_scopes`
- Add `channel_token_introspection_leeway`
- Add `channel_token_introspection_scopes_required`
- Add `channel_token_introspection_scopes_claim`
- Add `verify_channel_token_introspection_expiry`
- Add `verify_channel_token_introspection_scopes`

## v0.0.5

- Add `access_token_introspection_body_args`
- Add `channel_token_introspection_body_args`

## v0.0.4

- Add documentation
- Add `config.access_token_keyset`
- Add `config.channel_token_keyset`
- Add `config.cache_access_token_introspection`
- Add `config.cache_channel_token_introspection`
- Change `config.access_token_introspection_claim` to support nested claims (similar to `config.access_token_scopes_claim`).
- Change `config.channel_token_introspection_claim` to support nested claims (similar to `config.channel_token_scopes_claim`).

## v0.0.3

- Plugin renamed to `jwt-signer`, also affects the Github repository as well.

## v0.0.2

- Fix jwks.updated_at to correctly update on key rotation.

## v0.0.1

- Initial release.
