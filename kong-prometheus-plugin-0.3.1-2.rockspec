package = "kong-prometheus-plugin"
version = "0.3.1-2"

source = {
  url = "git://github.com/Kong/kong-plugin-prometheus",
  tag = "0.3.1"
}

supported_platforms = {"linux", "macosx"}
description = {
  summary = "Prometheus metrics for Kong and upstreams configured in Kong",
  license = "Apache 2.0",
}

dependencies = {
  --"kong >= 0.13.0",
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.prometheus.api"] = "kong/plugins/prometheus/api.lua",
    ["kong.plugins.prometheus.exporter"] = "kong/plugins/prometheus/exporter.lua",
    ["kong.plugins.prometheus.handler"] = "kong/plugins/prometheus/handler.lua",
    ["kong.plugins.prometheus.prometheus"] = "kong/plugins/prometheus/prometheus.lua",
    ["kong.plugins.prometheus.serve"] = "kong/plugins/prometheus/serve.lua",
    ["kong.plugins.prometheus.schema"] = "kong/plugins/prometheus/schema.lua",
  }
}
