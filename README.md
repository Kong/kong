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

  - *Request span*: 1 per request. Encompasses the whole request in kong (kind: `SERVER`).
    The proxy span and balancer spans are children of this span.
    Contains logs/annotations for the `kong.rewrite` phase start and end
  - *Proxy span*: 1 per request. Encompassing most of Kong's internal processing of a request (kind: `CLIENT`)
    Contains logs/annotations for the rest start/end of the rest of the kong phases:
    `kong.access`, `kong.header_filter`, `kong.body_filter`, `kong.preread`
  - *Balancer span(s)*: 0 or more per request, each encompassing one balancer attempt (kind: `CLIENT`)
    Contains tags specific to the load balancing:
    - `kong.balancer.try`: a number indicating the attempt order
    - `peer.ipv4`/`peer.ipv6` + `peer.port` for the balanced port
    - `error`: true/false depending on whether the balancing could be done or not
    - `http.status_code`: the http status code received, in case of error
    - `kong.balancer.state`: an nginx-specific description of the error: `next`/`failed` for HTTP failures, `0` for stream failures.
      Equivalent to `state_name` in [OpenResty's Balancer's `get_last_failure` function](https://github.com/openresty/lua-resty-core/blob/master/lib/ngx/balancer.md#get_last_failure).

## Tags

### Standard tags

"Standard" tags are documented [here](https://github.com/opentracing/specification/blob/master/semantic_conventions.md)
Of those, this plugin currently uses:

  - `span.kind` (sent to Zipkin as "kind")
  - `http.method`
  - `http.status_code`
  - `http.path`
  - `error`
  - `peer.ipv4`
  - `peer.ipv6`
  - `peer.port`
  - `peer.hostname`
  - `peer.service`


### Non-Standard tags

In addition to the above standardised tags, this plugin also adds:

  - `component` (sent to Zipkin as "lc", for "local component")
  - `kong.api` (deprecated)
  - `kong.consumer`
  - `kong.credential`
  - `kong.node.id`
  - `kong.route`
  - `kong.service`
  - `kong.balancer.try`
  - `kong.balancer.state`

## Logs / Annotations

Logs (annotations in Zipkin) are used to encode the begin and end of every kong phase.

  - `kong.rewrite`, `start` / `finish`, `<timestamp>`
  - `kong.access`, `start` / `finish`, `<timestamp>`
  - `kong.preread`, `start` / `finish`, `<timestamp>`
  - `kong.header_filter`, `start` / `finish`, `<timestamp>`
  - `kong.body_filter`, `start` / `finish`, `<timestamp>`

They are transmitted to Zipkin as annotations where the `value` is the concatenation of the log name and the value.

For example, the `kong.rewrite`, `start` log would be transmitted as:

  - `{ "value" = "kong.rewrite.start", timestamp = <timestamp> }`

