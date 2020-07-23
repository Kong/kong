[![Build Status][badge-travis-image]][badge-travis-url]

# Kong request transformer plugin

[badge-travis-url]: https://travis-ci.com/Kong/kong-plugin-request-transformer/branches
[badge-travis-image]: https://travis-ci.com/Kong/kong-plugin-request-transformer.svg?token=BfzyBZDa3icGPsKGmBHb&branch=master

## Synopsis

This plugin transforms the request sent by a client on the fly on Kong, before hitting the upstream server. It can match complete or portions of incoming requests using regular expressions, save those matched strings into variables, and substitute those strings into transformed requests via flexible templates.

## Configuration

### Enabling the plugin on a Service

Configure this plugin on a Service by making the following request:

```bash
$ curl -X POST http://kong:8001/services/{service}/plugins \
    --data "name=request-transformer"
```

`service`: the `id` or `name` of the Service that this plugin configuration will target.

### Enabling the plugin on a Route

Configure this plugin on a Route with:

```bash
$ curl -X POST http://kong:8001/routes/{route_id}/plugins \
    --data "name=request-transformer"
```

`route_id`: the `id` of the Route that this plugin configuration will target.

### Enabling the plugin on a Consumer
You can use the `http://localhost:8001/plugins` endpoint to enable this plugin on specific Consumers:

```bash
$ curl -X POST http://kong:8001/plugins \
    --data "name=request-transformer" \
    --data "consumer_id={consumer_id}"
```

Where `consumer_id` is the `id` of the Consumer we want to associate with this plugin.

You can combine `consumer_id` and `service_id` in the same request, to furthermore narrow the scope of the plugin.

| form parameter                                    | default             | description                                                                                                                                                                                        |
| ---                                               | ---                 | ---                                                                                                                                                                                                |
| `name`                                            |                     | The name of the plugin to use, in this case `request-transformer`
| `service_id`                                      |                     | The id of the Service which this plugin will target.
| `route_id`                                        |                     | The id of the Route which this plugin will target.
| `enabled`                                         | `true`              | Whether this plugin will be applied.
| `consumer_id`                                     |                     | The id of the Consumer which this plugin will target.
| `config.http_method`                              |                     | Changes the HTTP method for the upstream request
| `config.remove.headers`                           |                     | List of header names. Unset the headers with the given name.
| `config.remove.querystring`                       |                     | List of querystring names. Remove the querystring if it is present.
| `config.remove.body`                              |                     | List of parameter names. Remove the parameter if and only if content-type is one the following [`application/json`,`multipart/form-data`, `application/x-www-form-urlencoded`] and parameter is present.
| `config.replace.headers`                          |                     | List of headername:value pairs. If and only if the header is already set, replace its old value with the new one. Ignored if the header is not already set.
| `config.replace.querystring`                      |                     | List of queryname:value pairs. If and only if the querystring name is already set, replace its old value with the new one. Ignored if the header is not already set.
| `config.replace.uri`                              |                     | Updates the upstream request URI with given value. This value can only be used to update the path part of the URI, not the scheme, nor the hostname.
| `config.replace.body`                             |                     | List of paramname:value pairs. If and only if content-type is one the following [`application/json`,`multipart/form-data`, `application/x-www-form-urlencoded`] and the parameter is already present, replace its old value with the new one. Ignored if the parameter is not already present.
| `config.rename.headers`                           |                     | List of headername:value pairs. If and only if the header is already set, rename the header. The value is unchanged. Ignored if the header is not already set.
| `config.rename.querystring`                       |                     | List of queryname:value pairs. If and only if the field name is already set, rename the field name. The value is unchanged. Ignored if the field name is not already set.
| `config.rename.body`                              |                     | List of parameter name:value pairs. Rename the parameter name if and only if content-type is one the following [`application/json`,`multipart/form-data`, `application/x-www-form-urlencoded`] and parameter is present.
| `config.add.headers`                              |                     | List of headername:value pairs. If and only if the header is not already set, set a new header with the given value. Ignored if the header is already set.
| `config.add.querystring`                          |                     | List of queryname:value pairs. If and only if the querystring name is not already set, set a new querystring with the given value. Ignored if the querystring name is already set.
| `config.add.body`                                 |                     | List of paramname:value pairs. If and only if content-type is one the following [`application/json`,`multipart/form-data`, `application/x-www-form-urlencoded`] and the parameter is not present, add a new parameter with the given value to form-encoded body. Ignored if the parameter is already present.
| `config.append.headers`                           |                     | List of headername:value pairs. If the header is not set, set it with the given value. If it is already set, a new header with the same name and the new value will be set.
| `config.append.querystring`                       |                     | List of queryname:value pairs. If the querystring is not set, set it with the given value. If it is already set, a new querystring with the same name and the new value will be set.
| `config.append.body`                              |                     | List of paramname:value pairs. If the content-type is one the following [`application/json`, `application/x-www-form-urlencoded`], add a new parameter with the given value if the parameter is not present, otherwise if it is already present, the two values (old and new) will be aggregated in an array. |

**Notes**:

* If the value contains a `,` then the comma-separated format for lists cannot be used. The array notation must be used instead.
* The `X-Forwarded-*` fields are non-standard header fields written by Nginx to inform the upstream about client details and can't be overwritten by this plugin. If you need to overwrite these header fields, see the [post-function plugin in Serverless Functions](https://docs.konghq.com/hub/kong-inc/serverless-functions/).

## Template as Value

You can use any of the current request headers, query params, and captured URI groups as a template to populate the above supported configuration fields.

| Request Param | Template
| ------------- | -----------
| header        | `$(headers.<header_name>)`, `$(headers["<Header-Name>"])` or `$(headers["<header-name>"])`)
| querystring   | `$(query_params.<query-param-name>)` or `$(query_params["<query-param-name>"])`)
| captured URIs | `$(uri_captures.<group-name>)` or `$(uri_captures["<group-name>"])`)

To escape a template, wrap it inside quotes and pass it inside another template.<br>
`$('$(some_escaped_template)')`

Note: The plugin creates a non-mutable table of request headers, querystrings, and captured URIs before transformation. Therefore, any update or removal of params used in template does not affect the rendered value of a template.

### Advanced templates

The content of the placeholder `$(...)` is evaluated as a Lua expression, so
logical operators may be used. For example:

    Header-Name:$(uri_captures["user-id"] or query_params["user"] or "unknown")

This will first look for the path parameter (`uri_captures`). If not found, it will
return the query parameter. If that also doesn't exist, it returns the default
value '"unknown"'.

Constant parts can be specified as part of the template outside the dynamic
placeholders. For example, creating a basic-auth header from a query parameter
called `auth` that only contains the base64-encoded part:

    Authorization:Basic $(query_params["auth"])

Lambdas are also supported if wrapped as an expression like this:

    $((function() ... implementation here ... end)())

A complete Lambda example for prefixing a header value with "Basic" if not
already there:

    Authorization:$((function()
        local value = headers.Authorization
        if not value then
          return
        end
        if value:sub(1, 6) == "Basic " then
          return value            -- was already properly formed
        end
        return "Basic " .. value  -- added proper prefix
      end)())

*NOTE:* Especially in multi-line templates like the example above, make sure not
to add any trailing white-space or new-lines. Because these would be outside the
placeholders, they would be considered part of the template, and hence would be
appended to the generated value.

The environment is sandboxed, meaning that Lambdas will not have access to any
library functions, except for the string methods (like `sub()` in the example
above).

### Examples Using Template as Value

Add an API `test` with `uris` configured with a named capture group `user_id`

```bash
$ curl -X POST http://localhost:8001/apis \
    --data 'name=test' \
    --data 'upstream_url=http://mockbin.com' \
    --data-urlencode 'uris=/requests/user/(?<user_id>\w+)' \
    --data "strip_uri=false"
```

Enable the ‘request-transformer’ plugin to add a new header `x-consumer-id`
whose value is being set with the value sent with header `x-user-id` or
with the default value `alice` is `header` is missing.

```bash
$ curl -X POST http://localhost:8001/apis/test/plugins \
    --data "name=request-transformer" \
    --data-urlencode "config.add.headers=x-consumer-id:\$(headers['x-user-id'] or 'alice')" \
    --data "config.remove.headers=x-user-id"
```

Now send a request without setting header `x-user-id`

```bash
$ curl -i -X GET localhost:8000/requests/user/foo
```

Plugin will add a new header `x-consumer-id` with value `alice` before proxying
request upstream. Now try sending request with header `x-user-id` set

```bash
$ curl -i -X GET localhost:8000/requests/user/foo \
  -H "X-User-Id:bob"
```

This time the plugin will add a new header `x-consumer-id` with the value sent along
with the header `x-user-id`, i.e.`bob`

## Order of execution

Plugin performs the response transformation in the following order:

* remove → rename → replace → add → append

## Examples

<div class="alert alert-info.blue" role="alert">
  <strong>Kubernetes users:</strong> version <code>v1beta1</code> of the Ingress
  specification does not allow the use of named regex capture groups in paths.
  If you use the ingress controller, you should use unnamed groups, e.g.
  <code>(\w+)/</code> instead of <code>(?&lt;user_id&gt;\w+)</code>. You can access
  these based on their order in the URL path, e.g. <code>$(uri_captures[1])</code>
  will obtain the value of the first capture group.
</div>

In these examples we have the plugin enabled on a Service. This would work
similarly for Routes.

- Add multiple headers by passing each header:value pair separately:

**With a database**

```bash
$ curl -X POST http://localhost:8001/services/example-service/plugins \
  --data "name=request-transformer" \
  --data "config.add.headers[1]=h1:v1" \
  --data "config.add.headers[2]=h2:v1"
```

** Without a database **

```yaml
plugins:
- name: request-transformer
  config:
    add:
      headers: ["h1:v1", "h2:v1"]
```

<table>
  <tr>
    <th>incoming request headers</th>
    <th>upstream proxied headers:</th>
  </tr>
  <tr>
    <td>h1: v1</td>
    <td>
      <ul>
        <li>h1: v1</li>
        <li>h2: v1</li>
      </ul>
    </td>
  </tr>
</table>

- Add multiple headers by passing comma separated header:value pair (only possible with a database):

```bash
$ curl -X POST http://localhost:8001/services/example-service/plugins \
  --data "name=request-transformer" \
  --data "config.add.headers=h1:v1,h2:v2"
```

<table>
  <tr>
    <th>incoming request headers</th>
    <th>upstream proxied headers:</th>
  </tr>
  <tr>
    <td>h1: v1</td>
    <td>
      <ul>
        <li>h1: v1</li>
        <li>h2: v1</li>
      </ul>
    </td>
  </tr>
</table>

- Add multiple headers passing config as JSON body (only possible with a database):

```bash
$ curl -X POST http://localhost:8001/services/example-service/plugins \
  --header 'content-type: application/json' \
  --data '{"name": "request-transformer", "config": {"add": {"headers": ["h1:v2", "h2:v1"]}}}'
```

<table>
  <tr>
    <th>incoming request headers</th>
    <th>upstream proxied headers:</th>
  </tr>
  <tr>
    <td>h1: v1</td>
    <td>
      <ul>
        <li>h1: v1</li>
        <li>h2: v1</li>
      </ul>
    </td>
  </tr>
</table>

- Add a querystring and a header:

** With a database **

```bash
$ curl -X POST http://localhost:8001/services/example-service/plugins \
  --data "name=request-transformer" \
  --data "config.add.querystring=q1:v2,q2:v1" \
  --data "config.add.headers=h1:v1"
```

** Without a database **

```yaml
plugins:
- name: request-transformer
  config:
    add:
      headers: ["h1:v1"],
      querystring: ["q1:v1", "q2:v2"]

```

<table>
  <tr>
    <th>incoming request headers</th>
    <th>upstream proxied headers:</th>
  </tr>
  <tr>
    <td>h1: v2</td>
    <td>
      <ul>
        <li>h1: v2</li>
        <li>h2: v1</li>
      </ul>
    </td>
  </tr>
  <tr>
    <td>h3: v1</td>
    <td>
      <ul>
        <li>h1: v1</li>
        <li>h2: v1</li>
        <li>h3: v1</li>
      </ul>
    </td>
  </tr>
</table>

|incoming request querystring | upstream proxied querystring
|---           | ---
| ?q1=v1       |  ?q1=v1&q2=v1
|              |  ?q1=v2&q2=v1

- Append multiple headers and remove a body parameter:

** With a database **

```bash
$ curl -X POST http://localhost:8001/services/example-service/plugins \
  --header 'content-type: application/json' \
  --data '{"name": "request-transformer", "config": {"append": {"headers": ["h1:v2", "h2:v1"]}, "remove": {"body": ["p1"]}}}'
```

** Without a database **

``` yaml
plugins:
- name: request-transformer
  config:
    add:
      headers: ["h1:v1", "h2:v1"]
    remove:
      body: [ "p1" ]

```

<table>
  <tr>
    <th>incoming request headers</th>
    <th>upstream proxied headers:</th>
  </tr>
  <tr>
    <td>h1: v1</td>
    <td>
      <ul>
        <li>h1: v1</li>
        <li>h1: v2</li>
        <li>h2: v1</li>
      </ul>
    </td>
  </tr>
</table>

|incoming url encoded body | upstream proxied url encoded body
|---           | ---
|p1=v1&p2=v1   | p2=v1
|p2=v1         | p2=v1

