[![Build Status][badge-travis-image]][badge-travis-url]

# Kong proxy-cache plugin

HTTP Proxy Caching for Kong

## Synopsis

This plugin provides a reverse proxy cache implementation for Kong. It caches response entities based on configurable response code and content type, as well as request method. It can cache per-Consumer or per-API. Cache entities are stored for a configurable period of time, after which subsequent requests to the same resource will re-fetch and re-store the resource. Cache entities can also be forcefully purged via the Admin API prior to their expiration time.

## Configuration

Configuring the plugin is straightforward, you can add it on top of an existing API by executing the following request on your Kong server:

```bash
$ curl -X POST http://kong:8001/apis/{api}/plugins \
    --data "name=proxy-cache" \
    --data "config.strategy=memory"
```

`api`: The `id` or `name` of the API that this plugin configuration will target.

You can also apply it for every API using the `http://kong:8001/plugins/` endpoint.

| form parameter                                    | default             | description                                                                                                                                                                                        |
| ---                                               | ---                 | ---                                                                                                                                                                                                |
| `name`                                            |                     | The name of the plugin to use, in this case: `proxy-cache`                                                                                                                                         |
| `config.response_code`                            | `200`, `301`, `404` | Upstream response status code considered cacheable.                                                                                                                                                |
| `config.request_method`                           | `GET`, `HEAD`       | Downstream request methods considered cacheable.                                                                                                                                                   |
| `config.content_type`                             | `text/plain`,`application/json` | Upstream response content types considered cachable.                                                                                                                                   |
| `config.vary_headers`                             |                     | Relevant headers considered for the cache key. If undefined, none of the headers are taken into consideration                                                                                      |
| `config.vary_query_params`                        |                     | Relevant query parameters considered for the cache key. If undefined, all params are taken into consideration                                                                                      |
| `config.cache_ttl`                                | `300`               | TTL, in seconds, of cache entities.                                                                                                                                                                |
| `config.cache_control`                            | `false`             | When enabled, respect the Cache-Control behaviors defined in RFC 7234.                                                                                                                             |
| `config.storage_ttl`                              |                     | Number of seconds to keep resources in the storage backend. This value is independent of `cache_ttl` or resource TTLs defined by Cache-Control behaviors.                                          |
| `config.strategy`                                 |                     | The backing data store in which to hold cache entities. This version supports only `memory` strategy.                                                                                              |
| `config.memory.dictionary_name`                   | `kong_db_cache`     | The name of the shared dictionary in which to hold cache entities when the `memory` strategy is selected. Note that this dictionary currently must be defined manually in the Kong Nginx template. |


## Notes

### Strategies

The `proxy-cache` plugin is designed to support storing proxy cache data in different backend formats. Currently `memory` is the only strategy provided, using a `lua_shared_dict`. Note that the default dictionary, `kong_db_cache`, is also used by other plugins and elements of Kong to store unrelated database cache entities. Using this dictionary is an easy way to bootstrap the proxy-cache plugin, but it is not recommended for large-scale installations as significant usage will put pressure on other facets of Kong's database caching operations. It is recommended to define a separate `lua_shared_dict` via a custom Nginx template at this time.

### Cache Key

Kong keys each cache elements based on the request method, the full
client request (e.g., the request path and query parameters), and the
UUID of either the API or Consumer associated with the request. This
also implies that caches are distinct between APIs and/or
Consumers. The cache format can be tuned to enable some headers to be
part of it and also enable just a subset of the query
parameters. Internally, cache keys are represented as a
hexadecimal-encoded MD5 sum of the concatenation of the constituent
parts. This is calculated as follows:

```
key = md5(UUID | method | path | query_params | headers? )
```

Where `method` is defined via the OpenResty `ngx.req.get_method()`
call, and `path` is defined via the Nginx `$request` variable without
query parameters. `query_params` will default to *ALL*
query_parameters of the request. `headers?` contains the headers
defined in `vary_headers`. `vary_headers` defaults to *NONE*.  More
fine grained granularity can be achieved by setting the config
variable `vary_query_params` and `vary_headers` to the desired list of
parameters or headers that should be taken into account for a key.

For performance reasons, only 100 headers will be parsed looking for
desired headers to be part of the cache key.

Kong will return the cache key associated with a given request as the
`X-Cache-Key` response header. It is also possible to precalculate the
cache key for a given request as noted above. quey

### Cache Control

When the `cache_control` configuration option is enabled, Kong will respect request and response Cache-Control headers as defined by RFC7234, with a few exceptions:

* Cache revalidation is not yet supported, and so directives such as `proxy-revalidate` are ignored.
* Similarly, the behavior of `no-cache` is simplified to exclude the entity from being cached entirely.
* Secondary key calculation via `Vary` is not yet supported.

### Cache Status

Kong identifies the status of the request's proxy cache behavior via the `X-Cache-Status` header. There are several possible values for this header:

* `Miss`: The request could be satisfied in cache, but an entry for the resource was not found in cache, and the request was proxied upstream.
* `Hit`: The request was satisfied and served from cache.
* `Refresh`: The resource was found in cache, but could not satisfy the request, due to `Cache-Control` behaviors or reaching its hard-coded `cache_ttl` threshold.
* `Bypass`: The request could not be satisfied from cache based on plugin configuration.

### Storage TTL

Kong can store resource entities in the storage engine longer than the prescribed `cache_ttl` or `Cache-Control` values indicate. This allows Kong to maintain a cached copy of a resource past its expiration. This allows clients capable of using `max-age` and `max-stale` headers to request stale copies of data if necessary.

### Upstream Outages

Due to an implementation in Kong's core request processing model, at this point the `proxy-cache` plugin cannot be used to serve stale cache data when an upstream is unreachable. To equip Kong to serve cache data in place of returning an error when an upstream is unreachable, we recommend defining a very large `storage_ttl` (on the order of hours or days) in order to keep stale data in the cache. In the event of an upstream outage, stale data can be considered "fresh" by increasing the `cache_ttl` plugin configuration value. By doing so, data that would have been previously considered stale is now served to the client, before Kong attempts to connect to a failed upstream service.

## Admin API

This plugin provides several endpoints to managed cache entities. These endpoints are assigned to the `proxy-cache` RBAC resource.

The following endpoints are provided on the Admin API to examine and purge cache entities:

### Retrieve a Cache Entity

Two separate endpoints are available: one to look up a known plugin instance, and another that searches all proxy-cache plugins data stores for the given cache key. Both endpoints have the same return value.

#### Endpoint

`GET /proxy-cache/:plugin_id/caches/:cache_id`

| Attributes | Description |
| --- | --- |
| `plugin_id` | The UUID of the proxy-cache plugin |
| `cache_id` | The cache entity key as reported by the `X-Cache-Key` response header |

#### Endpoint

`GET /proxy-cache/:cache_id`

| Attributes | Description |
| --- | --- |
| `cache_id` | The cache entity key as reported by the `X-Cache-Key` response header |

#### Response

`HTTP 200 OK` if the cache entity exists; `HTTP 404 Not Found` if the entity with the given key does not exist.


### Delete Cache Entity

Two separate endpoints are available: one to look up a known plugin instance, and another that searches all proxy-cache plugins data stores for the given cache key. Both endpoints have the same return value.

#### Endpoint

`DELETE /proxy-cache/:plugin_id/caches/:cache_id`

| Attributes | Description |
| --- | --- |
| `plugin_id` | The UUID of the proxy-cache plugin |
| `cache_id` | The cache entity key as reported by the `X-Cache-Key` response header |

#### Endpoint

`DELETE /proxy-cache/:cache_id`

| Attributes | Description |
| --- | --- |
| `cache_id` | The cache entity key as reported by the `X-Cache-Key` response header |

#### Response

`HTTP 204 No Content` if the cache entity exists; `HTTP 404 Not Found` if the entity with the given key does not exist.


### Purge All Cache Entities

#### Endpoint

`DELETE /proxy-cache/`

#### Response

`HTTP 204 No Content` if the cache entity exists.

Note that this endpoint purges all cache entities across all `proxy-cache` plugins.


[badge-travis-url]: https://travis-ci.com/Kong/kong-plugin-proxy-cache/branches
[badge-travis-image]: https://travis-ci.com/Kong/kong-plugin-proxy-cache.svg?token=BfzyBZDa3icGPsKGmBHb&branch=master
