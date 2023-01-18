-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

_G.kong = {
  -- XXX EE: kong.version is used in
  -- analytics/init.lua and fail if nil
  version = "x.y.z",
}

local protoc = require "protoc"
local pb = require "pb"
local analytics = require "kong.analytics"

local request_log = {
  auth_type = "key-auth",
  authenticated_entity = {
    id = "4135aa9dc1b842a653dea846903ddb95bfb8c5a10c504a7fa16e10bc31d1fdf0",
    consumer_id = ""
  },
  latencies = {
    request = 515,
    kong = 58,
    proxy = 457
  },
  service = {
    host = "konghq.com",
    name = "service",
    created_at = 1614232642,
    connect_timeout = 60000,
    id = "167290ee-c682-4ebf-bdea-e49a3ac5e260",
    protocol = "http",
    read_timeout = 60000,
    port = 80,
    path = "/anything",
    updated_at = 1614232642,
    write_timeout = 60000,
    retries = 5,
    ws_id = "54baa5a9-23d6-41e0-9c9a-02434b010b25"
  },
  request = {
    querystring = {},
    size = 138,
    uri = "/log",
    url = "http=//localhost:8000/log",
    headers = {
      host = "localhost:8000",
      ['accept-encoding'] = "gzip, deflate",
      ['user-agent'] = "HTTPie/2.4.0",
      accept = "*/*",
      connection = "keep-alive"
    },
    method = "GET"
  },
  tries = {
    {
      balancer_latency = 10,
      port = 80,
      balancer_start = 1614232668399,
      ip = "18.211.130.98"
    }
  },
  client_ip = "192.168.144.1",
  workspace = "54baa5a9-23d6-41e0-9c9a-02434b010b25",
  upstream_uri = "/anything",
  response = {
    headers = {
      ['content-type'] = "application/json",
      date = "Thu, 25 Feb 2021 05=57=48 GMT",
      connection = "close",
      ['access-control-allow-credentials'] = "true",
      ['content-length'] = 503,
      server = "gunicorn/19.9.0",
      via = "kong/2.2.1.0-enterprise-edition",
      ['x-kong-proxy-latency'] = 57,
      ['x-kong-upstream-latency'] = 457,
      ['access-control-allow-origin'] = "*"
    },
    status = 200,
    size = 827
  },
  route = {
    id = "78f79740-c410-4fd9-a998-d0a60a99dc9b",
    name = "route",
    paths = {
      "/log"
    },
    protocols = {
      "http"
    },
    strip_path = true,
    created_at = 1614232648,
    ws_id = "54baa5a9-23d6-41e0-9c9a-02434b010b25",
    request_buffering = true,
    updated_at = 1614232648,
    preserve_host = false,
    regex_priority = 0,
    response_buffering = true,
    https_redirect_status_code = 426,
    path_handling = "v0",
    service = {
      id = "167290ee-c682-4ebf-bdea-e49a3ac5e260"
    }
  },
  consumer = {
    id = "54baa5a9-23d6-41e0-9c9a-02434b010b25",
  },
  started_at = 1614232668342
}

describe("extract request log properly", function()
  it("extract payload info properly", function()
    local payload = analytics:create_payload(request_log)
    local expected = {
      auth = {
        id = "4135aa9dc1b842a653dea846903ddb95bfb8c5a10c504a7fa16e10bc31d1fdf0",
        type = "key-auth"
      },
      client_ip = "192.168.144.1",
      started_at = 1614232668342,
      upstream = {
        upstream_uri = "/anything"
      },
      request = {
        header_user_agent = "HTTPie/2.4.0",
        header_host = "localhost:8000",
        http_method = "GET",
        body_size = 138,
        uri = "/log"
      },
      response = {
        http_status = 200,
        body_size = 827,
        header_content_length = 503,
        header_content_type = "application/json"
      },
      route = {
        id = "78f79740-c410-4fd9-a998-d0a60a99dc9b",
        name = "route"
      },
      service = {
        id = "167290ee-c682-4ebf-bdea-e49a3ac5e260",
        name = "service",
        port = 80,
        protocol = "http"
      },
      latencies = {
        kong_gateway_ms = 58,
        upstream_ms = 457,
        response_ms = 515
      },
      tries = {
        {
          balancer_latency = 10,
          port = 80,
          ip = "18.211.130.98"
        }
      },
      consumer = {
        id = "54baa5a9-23d6-41e0-9c9a-02434b010b25",
      },
    }
    assert.are.same(expected, payload)
  end)
end)

describe("filter keywords from uri properly", function()
  it("split works properly with query parameters", function()
    local input = "/log?key=value&key2=value2"
    local output = analytics:split(input, "?")
    local expected = "/log"
    assert.are.same(expected, output[1])
  end)
  it("split works properly without query parameters", function()
    local input = "/log"
    local output = analytics:split(input, "?")
    local expected = "/log"
    assert.are.same(expected, output[1])
  end)
  it("verify the extraction works properly with query parameters", function()
    local request_log_one = request_log
    request_log_one.request.uri = "/log?key=value?key2=value2"
    local payload = analytics:create_payload(request_log_one)
    local expected = "/log"
    assert.are.same(expected, payload.request.uri)
  end)
  it("verify the extraction works properly without query parameters", function()
    local request_log_one = request_log
    request_log_one.request.uri = "/log"
    local payload = analytics:create_payload(request_log_one)
    local expected = "/log"
    assert.are.same(expected, payload.request.uri)
  end)
  it("verify the extraction works properly for upstream_uri with query parameters", function()
    local request_log_one = request_log
    request_log_one.upstream_uri = "/status/200?apikey=123"
    local payload = analytics:create_payload(request_log_one)
    local expected = "/status/200"
    assert.are.same(expected, payload.upstream.upstream_uri)
  end)
  it("verify the extraction works properly for upstream_uri without query parameters", function()
    local request_log_one = request_log
    request_log_one.upstream_uri = "/status/200"
    local payload = analytics:create_payload(request_log_one)
    local expected = "/status/200"
    assert.are.same(expected, payload.upstream.upstream_uri)
  end)
end)

describe("proto buffer", function()
  local p = protoc.new()
  p:addpath("kong/include/kong/model/analytics")
  p:loadfile("payload.proto")
  it("encode and decode data correctly", function()
    local payload = analytics:create_payload(request_log)
    local bytes = pb.encode("kong.model.analytics.RequestMetadata", payload)
    local decoded = pb.decode("kong.model.analytics.RequestMetadata", bytes)
    assert.are.same(payload, decoded)
  end)

  it("encode and decode defaults correctly", function()
    local payload = analytics:create_payload({})
    local bytes = pb.encode("kong.model.analytics.RequestMetadata", payload)
    local decoded = pb.decode("kong.model.analytics.RequestMetadata", bytes)
    local default = {
      client_ip = "",
      started_at = 0,
      upstream = {
        upstream_uri = ""
      },
      request = {
        header_user_agent = "",
        header_host = "",
        http_method = "",
        body_size = 0,
        uri = ""
      },
      response = {
        http_status = 0,
        body_size = 0,
        header_content_length = 0,
        header_content_type = ""
      },
      route = {
        id = "",
        name = ""
      },
      service = {
        id = "",
        name = "",
        port = 0,
        protocol = ""
      },
      latencies = {
        kong_gateway_ms = 0,
        upstream_ms = 0,
        response_ms = 0
      },
      tries = {},
      consumer = {
        id = "",
      },
      auth = {
        id = "",
        type = ""
      }
    }
    assert.are.same(default, decoded)
  end)
end)
