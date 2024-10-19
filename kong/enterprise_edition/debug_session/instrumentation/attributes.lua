-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local fmt = string.format

local KONG_PREFIX = "proxy.kong"

-- creating a mapping for OTEL Attribute conventions and ATC Router conventions
-- When assigning attributes in our tracing code, we need to have a stable naming convention
-- that allows for aliasing in case we support the same attribute in the ATC router already.
-- What the ATC Router defines -> https://docs.konghq.com/gateway/3.8.x/key-concepts/routes/expressions/#matching-fields
-- What OpenTelemetry defines -> https://opentelemetry.io/docs/specs/semconv/

local ATTRIBUTES = {
  -- https://opentelemetry.io/docs/specs/semconv/attributes-registry/client/
  CLIENT_ADDRESS = {
    name = "client.address",
    alias ="net.src.ip",
    type = "IpAddr",
    -- TODO: add a field that allows us to exclude
    -- these attributes from the sampler
    use_for_sampling = true,
  },
  CLIENT_PORT = {
    name = "client.port",
    alias ="net.src.port",
    type = "Int",
    use_for_sampling = true,
  },
  -- https://github.com/open-telemetry/semantic-conventions/blob/main/docs/general/attributes.md#destination
  DESTINATION_ADDRESS = {
    -- for Kong, this is an upstream
    name = "destination.address",
    type = "IpAddr",
    use_for_sampling = true,
  },
  -- https://opentelemetry.io/docs/specs/semconv/attributes-registry/server/
  -- In our case, this will be Kong Gateway.
  SERVER_ADDRESS = {
    name = "server.address",
    alias ="net.dst.ip",
    type = "IpAddr",
    use_for_sampling = true,
  },
  SERVER_PORT = {
    name = "server.port",
    alias ="net.dst.port",
    type = "Int",
    use_for_sampling = true,
  },
  -- https://github.com/open-telemetry/semantic-conventions/blob/main/docs/general/attributes.md#other-network-attributes
  NETWORK_PROTOCOL = {
    -- http; spdy; grpc
    name = "network.protocol.name",
    alias ="net.protocol",
    type = "String",
    use_for_sampling = true,
  },
  NETWORK_PROTOCOL_VERSION = {
    -- 1.1, 2.0
    name = "network.protocol.version",
    type = "String",
    use_for_sampling = true,
  },
  NETWORK_TRANSPORT = {
    -- tcp, udp
    name = "network.transport",
    type = "String",
    use_for_sampling = true,
  },
  URL_SCHEME = {
    -- https, http
    name = "url.scheme",
    -- an edgecase with ATC as atc allows you to specify the scheme as part of the protocol (like httpc)
    alias ="net.protocol",
    type = "String",
    use_for_sampling = true,
  },
  -- https://opentelemetry.io/docs/specs/semconv/http/http-spans/#http-client
  REQUEST_METHOD = {
    name = "http.request.method",
    alias ="http.method",
    type = "String",
    use_for_sampling = true,
  },
  -- TODO: NYI
  -- REQUEST_HEADER = {
  --   name = "http.request.header.<header_name>",
  --   alias ="http.headers.<header_name>",
  --   type = "String",
  -- },
  -- Hardcoding this for now until ^^^^^ is properly implemented
  HTTP_HOST_HEADER = {
    name = "http.request.header.host",
    alias ="http.host",
    type = "String",
    use_for_sampling = true,
  },
  URL_PATH = {
    name = "http.route",
    alias ="http.path",
    type = "String",
    use_for_sampling = true,
  },
  URL_FULL = {
    name = "url.full",
    type = "String",
    use_for_sampling = true,
  },
  URL_QUERY = {
    name = "url.query",
    type = "String",
  },
  HTTP_RESPONSE_STATUS_CODE = {
    name = "http.response.status_code",
    type = "Int",
    use_for_sampling = true,
  },
  NETWORK_PEER_ADDRESS = {
    name = "network.peer.address",
    type = "IpAddr",
    use_for_sampling = true,
  },
  NETWORK_PEER_NAME = {
    -- This is non-standard but it's available to us via the balancer
    name = "network.peer.name",
    type = "String",
    use_for_sampling = true,
  },
  NETWORK_PEER_PORT = {
    name = "network.peer.port",
    type = "Int",
    use_for_sampling = true,
  },
  -- responses headers, not yet supported
  -- RESPONSE_HEADER = {
  --   name = "http.response.header.<header_name>",
  -- },
  TLS_SERVER_NAME_INDICATION = {
    -- Deprecated in OTEL, replaced by "server.address"
    -- https://opentelemetry.io/docs/specs/semconv/attributes-registry/tls/#tls-deprecated-attributes
    name = "server.address",
    alias ="tls.sni",
    type = "String",
    use_for_sampling = true,
  },
  -- Anything non-standard will get a prefix of "proxy.kong."
  -- In conformance with https://opentelemetry.io/docs/specs/semconv/general/attribute-naming/#recommendations-for-application-developers
  -- Also, what we define as an entity can be seen as a generic resource, as defined here: https://opentelemetry.io/docs/specs/semconv/resource/#service
  KONG_SERVICE_ID = {
    name = fmt("%s.service.id", KONG_PREFIX),
    type = "String",
    use_for_sampling = true,
  },
  KONG_ROUTE_ID = {
    name = fmt("%s.route.id", KONG_PREFIX),
    type = "String",
    use_for_sampling = true,
  },
  KONG_CONSUMER_ID = {
    name = fmt("%s.consumer.id", KONG_PREFIX),
    type = "String",
    use_for_sampling = true,
  },
  KONG_UPSTREAM_ID = {
    name = fmt("%s.upstream.id", KONG_PREFIX),
    type = "String",
    use_for_sampling = true,
  },
  KONG_UPSTREAM_STATUS_CODE = {
    name = fmt("%s.upstream.status_code", KONG_PREFIX),
    type = "Int",
    use_for_sampling = true,
  },
  KONG_UPSTREAM_ADDR = {
    name = fmt("%s.upstream.addr", KONG_PREFIX),
    type = "IpAddr",
    use_for_sampling = true,
  },
  KONG_UPSTREAM_HOST = {
    name = fmt("%s.upstream.host", KONG_PREFIX),
    type = "String",
    use_for_sampling = true,
  },
  KONG_UPSTREAM_LB_ALGORITHM = {
    name = fmt("%s.upstream.lb_algorithm", KONG_PREFIX),
    type = "String",
  },
  KONG_TARGET_ID = {
    name = fmt("%s.target.id", KONG_PREFIX),
    type = "String",
    use_for_sampling = true,
  },
  KONG_PLUGIN_ID = {
    name = fmt("%s.plugin.id", KONG_PREFIX),
    type = "String",
  },
  KONG_SAMPLING_RULE = {
    name = fmt("%s.sampling_rule", KONG_PREFIX),
    type = "String",
  },
  KONG_REQUEST_ID = {
    name = fmt("%s.request.id", KONG_PREFIX),
    type = "String",
  },
  KONG_DNS_RECORD_DOMAIN = {
    name = fmt("%s.dns.record.domain", KONG_PREFIX),
    type = "String",
  },
  KONG_DNS_RECORD_IP = {
    name = fmt("%s.dns.record.ip", KONG_PREFIX),
    type = "String",
  },
  KONG_DNS_RECORD_PORT = {
    name = fmt("%s.dns.record.port", KONG_PREFIX),
    type = "Int",
  },
  KONG_DNS_TRIES = {
    name = fmt("%s.dns.tries", KONG_PREFIX),
    type = "Array",
  },
  -- TIMING INFORMATION
  KONG_UPSTREAM_TTFB_MS = {
    name = fmt("%s.upstream.ttfb_ms", KONG_PREFIX),
    type = "Int",
    use_for_sampling = true,
  },
  KONG_UPSTREAM_READ_RESPONSE_DURATION_MS = {
    name = fmt("%s.upstream.read_response_duration_ms", KONG_PREFIX),
    type = "Int",
    use_for_sampling = true,
  },
  KONG_UPSTREAM_CONNECT_DURATION_MS = {
    name = fmt("%s.upstream.connect_duration_ms", KONG_PREFIX),
    type = "Int",
  },
  KONG_UPSTREAM_RESPONSE_DURATION_MS = {
    name = fmt("%s.upstream.response_duration_ms", KONG_PREFIX),
    type = "Int",
  },
  KONG_LATENCY_TOTAL_MS = {
    name = fmt("%s.latency_total_ms", KONG_PREFIX),
    type = "Int",
    use_for_sampling = true,
  },
  KONG_TOTAL_IO_REDIS_MS = {
    name = fmt("%s.redis.total_io_ms", KONG_PREFIX),
    type = "Int",
    use_for_sampling = true,
  },
  KONG_TOTAL_IO_TCPSOCKET_MS = {
    name = fmt("%s.tcpsock.total_io_ms", KONG_PREFIX),
    type = "Int",
    use_for_sampling = true,
  },
  -- DATABASE
  DB_SYSTEM = {
    name = "db.system",
    type = "String",
  },
  DB_STATEMENT = {
    name = "db.statement",
    type = "String",
  },
}

return {
  -- attributes that are specific to OpenTelemetry
  SPAN_ATTRIBUTES = (function()
    local otel_attributes = {}
    for k, v in pairs(ATTRIBUTES) do
      otel_attributes[k] = v.name
    end
    return otel_attributes
  end)(),
  -- attributes that we use for sampling
  SAMPLER_ATTRIBUTES = (function()
    local sampler_attrs = {}
    for k, v in pairs(ATTRIBUTES) do
      if v.use_for_sampling then
        -- remove from table
        v.use_for_sampling = nil
        sampler_attrs[k] = v
      end
    end
    return sampler_attrs
  end)(),
}
