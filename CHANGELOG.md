## 0.5.0

* Extend the load consumer logic to find a consumer by `username` and
`custom_id`; an oauth2 `username` maps to a consumer's `username`, while an
oauth2 `client_id` maps to a consumer's `custom_id`
* New configuration `consumer_by`: allows users to customize
which of `client_id` or `username` (returned by the introspection request)
is used to fetch a consumer
* new configuration `introspect_request`: if set to `true`, causes
the plugin to send information about the current request as headers in the
introspection endpoint request. Currently, request path and HTTP method are
sent as `X-Request-Path` and `X-Request-Http-Method` headers
* New configuration `custom_introspection_headers`: list of user-specified
headers to be sent in the introspection endpoint request
* New configuration `custom_claims_forward`: list of additional claims returned
by the introspection endpoint request to forward as headers to the upstream
service

## 0.4

* convert to new dao
* use pdk

## 0.3.3

* Set credential id to allow rate limiting based on access token

## 0.3.2

* Drop old RBAC migrations
* Rename rockspec

## 0.3.1

* Improve error handling in HTTP connections to introspection server

## 0.3

* Add support for anonymous users
* Add support for bypassing authorization on OPTIONS requests

## 0.2

- Initial tagged release
