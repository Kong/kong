[![Build Status][badge-travis-image]][badge-travis-url]

# Kong request transformer plugin

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

[badge-travis-url]: https://travis-ci.com/Kong/kong-plugin-request-transformer/branches
[badge-travis-image]: https://travis-ci.com/Kong/kong-plugin-request-transformer.svg?token=BfzyBZDa3icGPsKGmBHb&branch=master
