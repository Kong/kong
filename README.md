# Kong Prometheus Plugin

[![Build Status][badge-travis-image]][badge-travis-url]

This plugin exposes metrics in [Prometheus Exposition format](https://github.com/prometheus/docs/blob/master/content/docs/instrumenting/exposition_formats.md).


### Available metrics
- *Status codes*: HTTP status codes returned by upstream services. 
- *Latencies Histograms*: Latency as measured at Kong:
   - *Request*: Total request latency 
   - *Kong*: Time taken for Kong to route, authenticate and run all plugins for a request
   - *Upstream*: Time taken by the upstream to respond to the request.
- *Bandwidth*: Total Bandwidth (egress/ingress) flowing through Kong.
- *DB reachability*: Can the Kong node reach it's Database or not (Guage 0/1).
- *Connections*: Various NGINX connection metrics like active, reading, writing,
  accepted connections.

### Grafana Dashboard

Metrics collected via this plugin can be graphed using the following dashboard:
https://grafana.com/dashboards/7424

### Using the plugin

#### Enable the plugin
```bash
$ curl http://localhost:8001/plugins -d name=prometheus
```

### Scraping metrics

#### Via Kong's Admin API

Metrics are available on the admin API at `/metrics` endpoint:
```
curl http://localhost:8001/metrics
```

#### Via Kong's proxy

If your proxy nodes also serve the Admin API, then you can create a route
to `/metrics` endpoint and apply a IP restriction plugin.
```
curl -XPOST http://localhost:8001/services -d name=prometheusEndpoint -d url=http://localhost:8001/metrics
curl -XPOST http://localhost:8001/services/prometheusEndpoint/routes -d paths[]=/metrics
curl -XPOST http://localhost:8001/services/prometheusEndpoint/plugins -d name=ip-restriction -d config.whitelist=10.0.0.0/8
```

#### On a custom port

Alternatively, this plugin has the capability to serve the content on a
different port using a custom server block in Kong's NGINX template.

If you're using Kong 0.14.0 or above, then you can inject the server block
using Kong's [injecting NGINX directives](https://docs.konghq.com/0.14.x/configuration/#injecting-nginx-directives) 
feature.

Consider the below file containing an Nginx `server` block:

```
# /path/to/prometheus-server.conf
server {
    server_name kong_prometheus_exporter;
    listen 0.0.0.0:9542; # can be any other port as well

    location / {
        default_type text/plain;
        content_by_lua_block {
             local prometheus = require "kong.plugins.prometheus.exporter"
             prometheus:collect()
        }
    }

    location /nginx_status {
        internal;
        access_log off;
        stub_status;
    }
}
```

Assuming you've the above file available in your file-system on which
Kong is running, add the following line to your `kong.conf` to scrape metrics
from `9542` port.

```
nginx_http_include=/path/to/prometheus-server.conf
```

If you're running Kong version older than 0.14.0, then you can achieve the
same result by using a
[custom NGINX template](https://docs.konghq.com/0.14.x/configuration/#custom-nginx-templates-embedding-kong).

#### Sample /metrics output

```bash
$ curl http://localhost:8001/metrics
root@vagrant-ubuntu-trusty-64:~# curl -D - http://localhost:8001/metrics
HTTP/1.1 200 OK
Server: openresty/1.11.2.5
Date: Mon, 11 Jun 2018 01:39:38 GMT
Content-Type: text/plain; charset=UTF-8
Transfer-Encoding: chunked
Connection: keep-alive
Access-Control-Allow-Origin: *

# HELP kong_bandwidth Total bandwidth in bytes consumed per service in Kong
# TYPE kong_bandwidth counter
kong_bandwidth{type="egress",service="google"} 1277
kong_bandwidth{type="ingress",service="google"} 254
# HELP kong_datastore_reachable Datastore reachable from Kong, 0 is unreachable
# TYPE kong_datastore_reachable gauge
kong_datastore_reachable 1
# HELP kong_http_status HTTP status codes per service in Kong
# TYPE kong_http_status counter
kong_http_status{code="301",service="google"} 2
# HELP kong_latency Latency added by Kong, total request time and upstream latency for each service in Kong
# TYPE kong_latency histogram
kong_latency_bucket{type="kong",service="google",le="00001.0"} 1
kong_latency_bucket{type="kong",service="google",le="00002.0"} 1
.
.
.
kong_latency_bucket{type="kong",service="google",le="+Inf"} 2
kong_latency_bucket{type="request",service="google",le="00300.0"} 1
kong_latency_bucket{type="request",service="google",le="00400.0"} 1
.
.
kong_latency_bucket{type="request",service="google",le="+Inf"} 2
kong_latency_bucket{type="upstream",service="google",le="00300.0"} 2
kong_latency_bucket{type="upstream",service="google",le="00400.0"} 2
.
.
kong_latency_bucket{type="upstream",service="google",le="+Inf"} 2
kong_latency_count{type="kong",service="google"} 2
kong_latency_count{type="request",service="google"} 2
kong_latency_count{type="upstream",service="google"} 2
kong_latency_sum{type="kong",service="google"} 2145
kong_latency_sum{type="request",service="google"} 2672
kong_latency_sum{type="upstream",service="google"} 527
# HELP kong_nginx_http_current_connections Number of HTTP connections
# TYPE kong_nginx_http_current_connections gauge
kong_nginx_http_current_connections{state="accepted"} 8
kong_nginx_http_current_connections{state="active"} 1
kong_nginx_http_current_connections{state="handled"} 8
kong_nginx_http_current_connections{state="reading"} 0
kong_nginx_http_current_connections{state="total"} 8
kong_nginx_http_current_connections{state="waiting"} 0
kong_nginx_http_current_connections{state="writing"} 1
# HELP kong_nginx_metric_errors_total Number of nginx-lua-prometheus errors
# TYPE kong_nginx_metric_errors_total counter
kong_nginx_metric_errors_total 0

```



[badge-travis-url]: https://travis-ci.com/Kong/kong-plugin-prometheus/branches
[badge-travis-image]: https://travis-ci.com/Kong/kong-plugin-prometheus.svg?branch=master
