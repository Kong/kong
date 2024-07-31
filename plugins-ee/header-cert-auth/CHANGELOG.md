## Unreleased

- feat: add header-cert-auth CRL and OCSP proxy server support
- feat: add `allow_partial_chain` option to allow certificate verification with only an intermediate certificate.

## 0.3.5

- fix(handler) catch error in workspace_iter

## 0.3.4

- fix(handler) ensure certificate phase is set with ngx.ctx.KONG_PHASE

## 0.3.3

- fix(handler) ensure certificate phase is set in ngx.ctx

## 0.3.2

- fix(*) BasePlugin inheritance removal (FT-1701)
- tests(conf) Adding busted config to ensure we get STDOUT messages

## 0.3.1

- fix(header-cert-auth) Grab CA from the end of the proof chain instead of the beginning
- fix(schema) remove CA existence check (FTI-2296)

## 0.3.0

- fix(plugin) check the existence of all CAs when creating the plugin
- feat(header-cert-auth) add support for tags in the DAO

## 0.2.4

- fix(log) updating auth errors to handle fallthrough scenarios
- fix(route,ws) ensuring workspace options are used for cache lookups

## 0.2.3

- iterate over plugin instances in all workspaces

## 0.2.2

- chore(*) add copyright

## 0.2.1

- fix logging; ensure basic serializer generates `request.tls.client_verify`

## 0.2.0

- fix workspace fields (migration)

## 0.1.2

- skip verification when `IGNORE_CA_ERROR` is configured

## 0.1.1

- add `STRICT` mode

## 0.1.0

- add support for OCSP and CRL

## 0.0.9

- fix schema `consumer_id_by` => `consumer_id`

## 0.0.8

- exclude disabled `header-cert-auth` plugins when looking for SNIs

## 0.0.7

- add route filtering and customer lookup overrides

## 0.0.5

- add support for ACL
- add error message when CA certificate is missing
- return proper status code for authentication failures

## 0.0.4

- correct plugin iterator usage

## 0.0.3

- fix iteration of missing attributes

## 0.0.2

- fix incorrect default cache key when looking up credentials

## 0.0.1

- Initial release
