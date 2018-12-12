# Kong Session plugin

A [Kong] plugin to support implementing sessions for 
Kong authentication [plugins](https://docs.konghq.com/hub/).

## Usage

Kong Session plugin can be configured globally or per entity (service, route, etc)
and is always used in conjunction with another Kong [plugin].

## Configuration



## Description

Kong Session plugin can be used to manage browser sessions for APIs proxied
through the [Kong] API Gateway. It provides configuration and management for 
session data storage, encyption, renewal, expiry, and sending browser cookies 🍪.

> For more information on security, configs, and underlying session 
mechanism, check out [lua-resty-session] docs.

## Defaults

By default, Kong Session plugin favors security using a `Secure`, `HTTPOnly`, 
`Samesite=Strict` cookie. `domain` is automatically set using Nginx variable
host, but can be overridden.

## Session Data Storage

The session data can be stored in the cookie itself (encrypted) `storage=cookie`, or 
inside [Kong](#Kong-Storage-Adapter). The session data stores two context
variables:

```
ngx.ctx.authenticated_consumer.id
ngx.ctx.authenticated_credential.id
```

The plugin also sets a `ctx.authenticated_session` for communication between the
`access` and `header_filter` phases in the plugin.

## Kong Storage Adapter

Kong Session plugin extends the functionality of [lua-resty-session] with its own
session data storage adapter when `storage=kong`. This will store encrypted
session data into the current database strategy (e.g. postgres, cassandra etc.)
and the cookie will not contain any session data. Data stored in the database is
encrypted and the cookie will contain only the session id and HMAC signature. 
Sessions will use built-in Kong DAO ttl mechanism which destroys sessions after 
specified `cookie_lifetime` unless renewal occurs during normal browser activity.
It is recommended that you logout via XHR request or similar to manually handle
redirects.

### Logging Out

It is typical to provide users the ability to log out, or manually destroy, their
current session. Logging out is done via either query params or POST params in 
the request url. The configs `logout_methods` allows the plugin to limit logging
out based on HTTP verb. When `logout_query_arg` is set, it will check the 
presence of the url query param specified, and likewise when `logout_post_arg`
is set it will check the presence of the specified variable in the request body.
Allowed HTTP verbs are `GET`, `DELETE`, and `POST`. When there is a session 
present and the incoming request is a logout request, Kong Session plugin will 
return a 200 before continuing in the plugin run loop, and the request will not
continue to the upstream.

### Dependencies

Kong Session Plugin depends on [lua-resty-session](https://github.com/bungle/lua-resty-session).

#### Known Limitations

Due to limitations of OpenResty, the `header_filter` phase cannot connect to the
database, which poses a problem for initial retrieval of cookie (fresh session). 
There is a small window of time where cookie is sent to client, but database 
insert has not yet been committed, as database call is in `ngx.timer` thread. 
Current workaround is to wait some interval of time (~100-500ms) after 
`Set-Cookie` header is sent to client before making subsequent requests. This is
_not_ a problem during session renewal period as renew happens in `access` phase.

[Kong]: https://konghq.com
[plugin]: https://docs.konghq.com/hub/
[lua-resty-session]: https://github.com/bungle/lua-resty-session
