## v0.0.6

- Updated .VERSION property of all the plugins (sorry, forgot that in 0.0.5)

## v0.0.5

- Implement logout with optional revocation and rp initiated logout
- Implement passing dynamic arguments to authorization endpoint from client
- Add `config.authorization_query_args_client`
- Add `config.client_arg` configuration parameter
- Add `config.logout_redirect_uri`
- Add `config.logout_query_arg`
- Add `config.logout_post_arg`
- Add `config.logout_uri_suffix`
- Add `config.logout_methods`
- Add `config.logout_revoke`
- Add `config.revocation_endpoint`
- Add `config.end_session_endpoint`
- Change `config.login_redirect_uri` from `string` to `array`

## v0.0.4

- Add changelog
- Add config.login_redirect_mode configuration option
- Fix invalid re-verify to cleanup existing session 
- Update docs with removal of non-accessible uris
- Update .rockspec with new homepage and repository link

## v0.0.3

- First tagged release
