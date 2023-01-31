# DataDog Tracing Plugin

This plugin provides a way to trace requests to your Kong nodes using the Datadog APM tracer.

## Installation

0. Install Datadog Agent on your Kong nodes. See [Datadog documentation](https://docs.datadoghq.com/tracing/setup_overview/setup/go/?tab=containers) for more details.

1. Install the plugin using luarocks:

```bash
luarocks make
```

2. Add the plugin to your Kong configuration:

```bash
plugins = bundled,datadog-tracing
```

## Usage

The plugin can be configured globally or per service. If the plugin is configured globally, it will be applied to all services. If the plugin is configured per service, it will only be applied to that service.

### Demo

Setup DataDog Agent:

```
docker run -d -p 8126:8126 \
              --cgroupns host \
              --pid host \
              -v /var/run/docker.sock:/var/run/docker.sock:ro \
              -v /proc/:/host/proc/:ro \
              -v /sys/fs/cgroup/:/host/sys/fs/cgroup:ro \
              -e DD_API_KEY=<api-key> \
              -e DD_APM_NON_LOCAL_TRAFFIC=true \
              -e DD_APM_ENABLED=true \
              gcr.io/datadoghq/agent:latest
```

Setup Kong:

```bash
http DELETE :8001/upstreams/mockbin
http PUT :8001/upstreams/mockbin host_header=mockbin.org
http POST :8001/upstreams/mockbin/targets target=mockbin.org:80
http PUT :8001/services/mockbin host=mockbin
http PUT :8001/services/mockbin/routes/mockbin paths:='["/"]'

# cascade routes
http PUT :8001/services/cascade-1 url=http://localhost:8000/
http PUT :8001/services/cascade-1/routes/cascade-1 paths:='["/cascade-1"]'

http PUT :8001/services/cascade-2 url=http://localhost:8000/cascade-1
http PUT :8001/services/cascade-2/routes/cascade-2 paths:='["/cascade-2"]'

http PUT :8001/services/cascade-3 url=http://localhost:8000/cascade-2
http PUT :8001/services/cascade-3/routes/cascade-3 paths:='["/cascade-3"]'

http PUT :8001/services/cascade-4 url=http://localhost:8000/cascade-3
http PUT :8001/services/cascade-4/routes/cascade-4 paths:='["/cascade-4"]'

http PUT :8001/services/cascade-5 url=http://localhost:8000/cascade-4
http PUT :8001/services/cascade-5/routes/cascade-5 paths:='["/cascade-5"]'

# create dd tracing plugin
# the endpoint must be OTLP/HTTP compatible backend
# e.g. http://localhost:4318/v1/traces
http PUT :8001/plugins/f53fa56d-7d08-4f6e-8e00-99ad73b9eb86 \
  name=datadog-tracing \
  config:='{"endpoint":"http://localhost:8126/v0.4/traces", "service_name": "kong"}'

# wrk -t5 -c10 -d10s http://localhost:8000/
for i in {1..5}; do http http://localhost:8000/cascade-5; done
# http http://localhost:8000/cascade-5
```
