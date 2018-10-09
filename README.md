# Getting Started

## Get a running Zipkin instance

e.g. using docker:

```
sudo docker run -d -p 9411:9411 openzipkin/zipkin
```


## Enable the Plugin

```
curl --url http://localhost:8001/plugins/ -d name=zipkin -d config.http_endpoint=http://127.0.0.1:9411/api/v2/spans
```

See many more details of using this plugin at https://docs.konghq.com/plugins/zipkin/


# Implementation

The Zipkin plugin is derived from an OpenTracing base.

A tracer is created with the "http_headers" formatter set to use the headers described in [b3-propagation](https://github.com/openzipkin/b3-propagation)

## Spans

  - `kong.request`: encompasing the whole request in kong.
    All other spans are children of this.
  - `kong.rewrite`: encompassing the kong rewrite phase
  - `kong.proxy`: encompassing kong's time as a proxy
    - `kong.access`: encompassing the kong access phase
    - `kong.balancer`: each balancer phase will have it's own span
    - `kong.header_filter`: encompassing the kong header filter phase
    - `kong.body_filter`: encompassing the kong body filter phase


## Tags

### Standard tags

"Standard" tags are documented [here](https://github.com/opentracing/specification/blob/master/semantic_conventions.md)
Of those, this plugin currently uses:

  - `span.kind` (sent to Zipkin as "kind")
  - `http.method`
  - `http.status_code`
  - `http.url`
  - `peer.ipv4`
  - `peer.ipv6`
  - `peer.port`
  - `peer.hostname`
  - `peer.service`


### Non-Standard tags

In addition to the above standardised tags, this plugin also adds:

  - `kong.api` (deprecated)
  - `kong.consumer`
  - `kong.credential`
  - `kong.node.id`
  - `kong.route`
  - `kong.service`
  - `kong.balancer.try`
  - `kong.balancer.state`: see [here](https://github.com/openresty/lua-resty-core/blob/master/lib/ngx/balancer.md#get_last_failure) for possible values
  - `kong.balancer.code`
