# Kong Session plugin

[![Build Status][badge-travis-image]][badge-travis-url]

A [Kong] plugin to support implementing sessions for 
Kong authentication [plugins](https://docs.konghq.com/hub/).

## Description

Kong Session plugin can be used to manage browser sessions for APIs proxied
through the [Kong] API Gateway. It provides configuration and management for 
session data storage, encyption, renewal, expiry, and sending browser cookies 🍪.

> For more information on security, configs, and underlying session 
mechanism, check out [lua-resty-session] docs.

## Usage

Kong Session plugin can be configured globally or per entity (service, route, etc)
and is always used in conjunction with another Kong authentication [plugin]. This
plugin is intended to work similarly to the [multiple authentication] setup.

Once Kong Session plugin is enabled in conjunction with an authentication plugin,
it will run prior to credential verification. If no session is found, then the
authentication plugin will run and credentials will be checked as normal. If the
credential verification is successful, then the session plugin will create a new
session for usage with subsequent requests. When a new request comes in, and a
session is present, then Kong Session plugin will attach the ngx.ctx variables
to let the authentication plugin know that authentication has already occured via
session validation. Since this configuration is a logical OR scenario, it is desired
that anonymous access be forbidden, then the [request termination] plugin should
be configured on an anonymous consumer. Failure to do so will allow unauthorized
requests. For more information please see section on [multiple authentication].

For usage with [key-auth] plugin

1. ### Create an example Service and a Route

    Issue the following cURL request to create `example-service` pointing to 
    mockbin.org, which will echo the request:

    ```bash
    $ curl -i -X POST \
      --url http://localhost:8001/services/ \
      --data 'name=example-service' \
      --data 'url=http://mockbin.org/request'
    ```

    Add a route to the Service:

    ```bash
    $ curl -i -X POST \
      --url http://localhost:8001/services/example-service/routes \
      --data 'paths[]=/sessions-test'
    ```

    The url `http://localhost:8000/sessions-test` will now echo whatever is being 
    requested.

1. ### Configure the key-auth Plugin for the Service

    Issue the following cURL request to add the key-auth plugin to the Service:

    ```bash
    $ curl -i -X POST \
      --url http://localhost:8001/services/example-service/plugins/ \
      --data 'name=key-auth'
    ```

    Be sure to note the created Plugin `id` - it will be needed it in step 5.

1. ### Verify that the key-auth plugin is properly configured

    Issue the following cURL request to verify that the [key-auth][key-auth]
    plugin was properly configured on the Service:

    ```bash
    $ curl -i -X GET \
      --url http://localhost:8000/sessions-test
    ```

    Since the required header or parameter `apikey` was not specified, and 
    anonymous access was not yet enabled, the response should be `401 Unauthorized`:

1. ### Create a Consumer and an anonymous Consumer

    Every request proxied and authenticated by Kong must be associated with a 
    Consumer. You'll now create a Consumer named `anonymous_users` by issuing 
    the following request:

    ```bash
    $ curl -i -X POST \
      --url http://localhost:8001/consumers/ \
      --data "username=anonymous_users"
    ```

    Be sure to note the Consumer `id` - you'll need it in the next step.

    Now create a consumer that will authenticate via sessions
    ```bash
    $ curl -i -X POST \
      --url http://localhost:8001/consumers/ \
      --data "username=fiona"
    ```

1. ### Provision key-auth credentials for your Consumer
    
    ```bash
    $ curl -i -X POST \
      --url http://localhost:8001/consumers/fiona/key-auth/ \
      --data 'key=open_sesame'
    ```

1. ### Enable anonymous access

    You'll now re-configure the key-auth plugin to permit anonymous access by 
    issuing the following request (**replace the uuids below by the `id` value
    from previous steps**):

    ```bash
    $ curl -i -X PATCH \
      --url http://localhost:8001/plugins/<your-key-auth-plugin-id> \
      --data "config.anonymous=<anonymous_consumer_id>"
    ```

1. ### Add the Kong Session plugin to the service

    ```bash
    $ curl -X POST http://localhost:8001/services/example-service/plugins \
        --data "name=session"  \
        --data "config.storage=kong" \
        --data "config.cookie_secure=false"
    ```
    > Note: cookie_secure is true by default, and should always be true, but is set to
    false for the sake of this demo in order to avoid using HTTPS.

1. ### Add the Request Termination plugin

    To disable anonymous access to only allow users access via sessions or via
    authentication credentials, enable the Request Termination plugin.

    ```bash
    $ curl -X POST http://localhost:8001/services/example-service/plugins \
        --data "name=request-termination"  \
        --data "config.status_code=403" \
        --data "config.message=So long and thanks for all the fish!" \
        --data "consumer_id=<anonymous_consumer_id>"
    ```

    Anonymous requests now will return status `403`.

    ```bash
      $ curl -i -X GET \
        --url http://localhost:8000/sessions-test
    ```

    Should return `403`.

1. ### Verify that the session plugin is properly configured

    ```bash
    $ curl -i -X GET \
      --url http://localhost:8000/sessions-test?apikey=open_sesame
    ```

    The response should not have the `Set-Cookie` header. Make sure that this
    cookie works.

    If cookie looks like this:
    ```
    Set-Cookie: session=emjbJ3MdyDsoDUkqmemFqw..|1544654411|4QMKAE3I-jFSgmvjWApDRmZHMB8.; Path=/; SameSite=Strict; HttpOnly
    ```

    Use it like this:

    ```bash
      $ curl -i -X GET \
        --url http://localhost:8000/sessions-test \
        -H "cookie:session=emjbJ3MdyDsoDUkqmemFqw..|1544654411|4QMKAE3I-jFSgmvjWApDRmZHMB8."
    ```

    This request should succeed, and `Set-Cookie` response header will not appear
    until renewal period.

## Defaults

By default, Kong Session plugin favors security using a `Secure`, `HTTPOnly`, 
`Samesite=Strict` cookie. `cookie_domain` is automatically set using Nginx variable
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

## 🦍 Kong Storage Adapter

Kong Session plugin extends the functionality of [lua-resty-session] with its own
session data storage adapter when `storage=kong`. This will store encrypted
session data into the current database strategy (e.g. postgres, cassandra etc.)
and the cookie will not contain any session data. Data stored in the database is
encrypted and the cookie will contain only the session id and HMAC signature. 
Sessions will use built-in Kong DAO ttl mechanism which destroys sessions after 
specified `cookie_lifetime` unless renewal occurs during normal browser activity.
It is recommended that the application logout via XHR request or similar to 
manually handle redirects.

### 👋🏻 Logging Out

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
[multiple authentication]: https://docs.konghq.com/0.14.x/auth/#multiple-authentication
[key-auth]: https://docs.konghq.com/hub/kong-inc/key-auth/
[request termination]: https://docs.konghq.com/hub/kong-inc/request-termination/

[badge-travis-url]: https://travis-ci.com/Kong/kong-plugin-session/branches
[badge-travis-image]: https://travis-ci.com/Kong/kong-plugin-session.svg?token=BfzyBZDa3icGPsKGmBHb&branch=master
