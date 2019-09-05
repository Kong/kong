## v1.2.4

- Fix issue when discovery did not return issuer information, and which could lead
  to `500` error on `401` and `403` responses.
  

## v1.2.3

- Change invalidations to do local invalidation instead of cluster-wide invalidation
- Fix admin api to properly call cleanup function on entity endpoint
- Fix `hide_credentials` not clearing `X-Access-Token` header
- Chore debug logging to not log about disabled authentication methods 
- Chore TTL code and fix some edge cases


## v1.2.2

- Fix with a workaround an issue of current EE 0.35 calling `endpoints.page_collection` on
  `:8001/openid-connect/issuers`.


## v1.2.1

- Change more reentrant migrations (not a real issue, but for future)
- Remove developer status/type check from plugin EBB-56 


## v1.2.0

- Add `config.token_post_args_client`
- Add `config.instrospection_post_args_client`
- Add `config.session_cookie_renew`
- Fix Cassandra migration


## v1.1.0

- Add `config.authorization_endpoint`
- Add `config.token_endpoint`
- Add `config.response_type`
- Change `config.issuer` to semi-optional (you still need to specify it but code won't error if http request to issuer fails)
- Fix issue with Kong OAuth 2.0 and OpenID Connect sharing incompatible values with same cache key


## v1.0.0

- Change Kong 1.0 support
- Remove all the sub-plugins (`openid-connect-verification`, `openid-connect-authentication`, and `openid-connect-protection`)
- Update `lua-resty-http` to `>= 0.13`


## v0.2.8

- Add `config.token_headers_names`
- Add `config.token_headers_values`
- Add `config.introspection_post_args_names`
- Add `config.introspection_post_args_values`
- Add `config.session_secret`
- Add `config.ignore_signature`
- Add `config.cache_ttl_max`
- Add `config.cache_ttl_min`
- Add `config.cache_ttl_neg`
- Add `config.cache_ttl_resurrect`
- Add `config.upstream_session_id_header`
- Add `config.downstream_session_id_header`
- Add `tokens` option to `config.login_tokens` to return full token endpoint results with
  `response` or `redirect` specified in `config.login_action`
- Add `introspection` option to `config.login_tokens` to return introspection results with
  `response` or `redirect` specified in `config.login_action`
- Change Refresh-token headers can now have `Bearer` in front of the token.
- Change to forbid only unapproved developers (enterprise edition)
- Change `config.scopes_claim` is also searched in introspected jwt token results
- Change `config.audience_claim` is also searched in introspected jwt token results
- Change `config.consumer_claim` is also searched in introspected jwt token results
- Change `config.consumer_claim` is also searched with user info when `config.search_user_info` is enabled
- Change `config.credential_claim` is searched from `id token` as well
- Change `config.credential_claim` is also searched in introspected jwt token results
- Change `config.credential_claim` is also searched with user info when `config.search_user_info` is enabled
- Change `config.authenticated_groups_claim` is searched from `id token` as well
- Change `config.authenticated_groups_claim` is also searched with user info when `config.search_user_info` is enabled
- Change `config.upstream_headers_claims` and `config.downstream_headers_claims` are now
  searched from introspection results, jwt access token and id token,
  and user info when `config.search_user_info` is enabled
- Change `id_token` is not anymore copied over when refreshing tokens to prevent further claims verification errors.
  The token endpoint can return a new id token, or user info can be used instead.


## v0.2.7

- Remove `daos` that were never used
- Hide `secret` from admin api
- Bump `lua-resty-session` to `2.23`


## v0.2.6

- Fix schema `self_check` to verify `issuer` only when given (e.g. when `PATCH`ing).
- Add `config.http_proxy_authorization`
- Add `config.https_proxy_authorization`
- Add `config.no_proxy`
- Add `config.logout_revoke_access_token`
- Add `config.logout_revoke_refresh_token`
- Add `config.refresh_token_param_name`
- Add `config.refresh_token_param_type`
- Add `config.refresh_tokens`


## v0.2.5

- Add `sub-plugins` back to `.rockspec` too, :-/.


## v0.2.4

- Fix a bug that prevented `sub-plugins` from loading the `issuer` data.


## v0.2.3

- Add support for `X-Forwarded-*` headers in automatic `config.redirect_uri` generation
- Add `config.session_cookie_path`
- Add `config.session_cookie_domain`
- Add `config.session_cookie_samesite`
- Add `config.session_cookie_httponly`
- Add `config.session_cookie_secure`
- Add `config.authorization_cookie_path`
- Add `config.authorization_cookie_domain`
- Add `config.authorization_cookie_samesite`
- Add `config.authorization_cookie_httponly`
- Add `config.authorization_cookie_secure`
- Add back the deprecated `openid-connect-authentication` plugin one last time before final removal
- Add back the deprecated `openid-connect-protection` plugin one last time before final removal
- Add back the deprecated `openid-connect-verification` plugin one last time before final removal


## v0.2.2

- Change decoding needed for option features does not verify
  signature anymore (it is already verified earlier)
- Fix issue when using password grant or client credentials
  grant with token caching enabled, and rotating keys on IdP
  that caused the cached tokens to give 403. The cached tokens
  will now be flushed and new tokens will be retrieved from
  the IdP.
- Add `config.rediscovery_lifetime`


## v0.2.1

- IMPORTANT Change `config.ssl_verify` to default to `false`.
- Add `config.http_proxy`
- Add `config.https_proxy`
- Add `config.keepalive`
- Add `config.authenticated_groups_claim`
- Fix `expiry` leeway counting when there is refresh token
  available and when there is not.


## v0.2.0

- Change to always log the original error message when authorization code flow
  verification fails
- Fix cache.tokens_load ttl fallback to access token `exp` in case when `expires_in` is missing
- Fix headers to not set when header value is `ngx.null` (a bit more robust now)
- Fix encoding of complex upstream and downstream headers
- Fix multiple authentication plugins AND / OR scenarios
- Add `config.unauthorized_error_message`
- Add `config.forbidden_error_message`
- Optimize usage of `ngx.ctx` by loading it once and then passing it to functions
- Remove the deprecated `openid-connect-authentication` plugin
- Remove the deprecated `openid-connect-protection` plugin
- Remove the deprecated `openid-connect-verification` plugin


## v0.1.9

- Fix `ngx.ctx.authenticated_credential` was set when we didn't actually find
  a value with `config.credential_claim`
- Add check to `consumer.status` and return forbidden if consumer is unapproved
- Drop support for Kong distributions based on CE 0.10.x (or older)


## v0.1.8

- Change `config_consumer_claim` from `string` to `array`
- Add `config.consumer_optional`
- Add `config.token_endpoint_auth_method`
- Fix `kong_oauth2` auth_method so that it works without having to
  also add`bearer` or `introspection` to `config.auth_methods` 


## v0.1.7

- Change expired or non-active access tokens to give `401` instead of `403`
  to better follow: https://tools.ietf.org/html/rfc7231#section-6.5.3
- Add `config.introspect_jwt_tokens`


## v0.1.6

- Revert ill-merged RBACv2 PR #17.


## v0.1.5

- Change `self_check` to run only on `content` and `access` phases. 


## v0.1.4

- Fix `config.scopes` when set to `null` or `""` so that it doesn't add `openid`
  scope anymore.


## v0.1.3

- Add `config.extra_jwks_uris`
- Fix set headers when callback to get header value failed
- Rediscovery of JWKS is now cached
- Admin API self-check discovery


## v0.1.2

This release adds option that allows e.g. rate-limiting by arbitrary claim:

- Add `config.credential_claim`


## v0.1.1

- Bearer token is now looked up on `Access-Token` and `X-Access-Token` headers
  too.


## v0.1.0

This release only fixes some bugs in 0.0.9.

- Fix `exp` retrival
- Fix `jwt_session_cookie` verification
- Fix consumer mapping using introspection


## v0.0.9

With this release the whole code base got refactored and a lot of
new features were added. We also made the code a lot more robust.

This release deprecates:
- OpenID Connect Authentication Plugin
- OpenID Connect Protection Plugin
- OpenID Connect Verification Plugin

This release removes:
- Remove multipart parsing of id tokens (it was never proxy safe)

This release adds:
- Add `config.session_storage`
- Add `config.session_memcache_prefix`
- Add `config.session_memcache_socket`
- Add `config.session_memcache_host`
- Add `config.session_memcache_port`
- Add `config.session_redis_prefix`
- Add `config.session_redis_socket`
- Add `config.session_redis_host`
- Add `config.session_redis_port`
- Add `config.session_redis_auth`
- Add `config.session_cookie_lifetime`
- Add `config.authorization_cookie_lifetime`
- Add `config.forbidden_destroy_session`
- Add `config.forbidden_redirect_uri`
- Add `config.unauthorized_redirect_uri`
- Add `config.unexpected_redirect_uri`
- Add `config.scopes_required`
- Add `config.scopes_claim`
- Add `config.audience_required`
- Add `config.audience_claim`
- Add `config.discovery_headers_names`
- Add `config.discovery_headers_values`
- Add `config.introspection_hint`
- Add `config.introspection_headers_names`
- Add `config.introspection_headers_values`
- Add `config.token_exchange_endpoint`
- Add `config.cache_token_exchange`
- Add `config.bearer_token_param_type`
- Add `config.client_credentials_param_type`
- Add `config.password_param_type`
- Add `config.hide_credentials`
- Add `config.cache_ttl`
- Add `config.run_on_preflight`
- Add `config.upstream_headers_claims`
- Add `config.upstream_headers_names`
- Add `config.downstream_headers_claims`
- Add `config.downstream_headers_names`


## v0.0.8

NOTE: the way `config.anonymous` has changed in this release is a **BREAKING**
change **AND** can lead to **UNAUTHORIZED** access if old behavior was used.
Please use `acl` or `request-termination` plugins to restrict `anonymous`
access. The change was made so that that this plugin follows similar patterns
as other Kong Authentication plugins regarding to `config.anonymous`.

- In case of auth plugins concatenation, the OpenID Connect plugin now
  removes remnants of anonymous
- Fixed anonymous consumer mapping
- Anonymous consumer uses now a simple cache key that is used in other plugins
- `config.anonymous` now behaves similarly to other plugins and doesn't halt
  execution or proxying (previously it was used just as a fallback for consumer
  mapping) and the plugin always needed valid credentials to be allowed to proxy
  if the client wasn't already authenticated by higher priority auth plugin.
- Change if `anonymous` consumer is not found we return internal server error
  instead of forbidden
- Change `config.client_id` from `required` to `optional`
- Change `config.client_secret` from `required` to `optional`


## v0.0.7

- Fixed authorization code flow client selection


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
