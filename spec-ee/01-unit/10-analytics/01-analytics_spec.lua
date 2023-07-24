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

local utils = require "kong.tools.utils"
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

local request_log_rate_limit = {
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
      ['access-control-allow-origin'] = "*",
      ['ratelimit-limit'] = 10,
      ['ratelimit-remaining'] = 0,
      ['ratelimit-reset'] = 39,
      ['retry-after'] = 39,
      ['x-ratelimit-limit-day'] = 600,
      ['x-ratelimit-limit-hour'] = 500,
      ['x-ratelimit-limit-minute'] = 10,
      ['x-ratelimit-limit-month'] = 700,
      ['x-ratelimit-limit-second'] = 5,
      ['x-ratelimit-limit-year'] = 800,
      ['x-ratelimit-remaining-day'] = 580,
      ['x-ratelimit-remaining-hour'] = 480,
      ['x-ratelimit-remaining-minute'] = 0,
      ['x-ratelimit-remaining-month'] = 680,
      ['x-ratelimit-remaining-second'] = 5,
      ['x-ratelimit-remaining-year'] = 780
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
  local trace_bytes = utils.get_rand_bytes(16)

  before_each(function()
    ngx.ctx["KONG_SPANS"] = {{
        trace_id = trace_bytes,
        should_sample = true
      }
    }
  end)

  after_each(function()
    ngx.ctx.KONG_SPANS = nil
  end)

  it("extract payload info properly dont sample trace_id", function()
    ngx.ctx["KONG_SPANS"][1].should_sample = false
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
        uri = "/log",
      },
      response = {
        http_status = 200,
        body_size = 827,
        header_content_length = 503,
        header_content_type = "application/json",
        ratelimit_enabled = false,
        ratelimit_enabled_second = false,
        ratelimit_enabled_minute = false,
        ratelimit_enabled_hour = false,
        ratelimit_enabled_day = false,
        ratelimit_enabled_month = false,
        ratelimit_enabled_year = false

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
      trace_id = "",
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
        uri = "/log",
      },
      response = {
        http_status = 200,
        body_size = 827,
        header_content_length = 503,
        header_content_type = "application/json",
        ratelimit_enabled = false,
        ratelimit_enabled_second = false,
        ratelimit_enabled_minute = false,
        ratelimit_enabled_hour = false,
        ratelimit_enabled_day = false,
        ratelimit_enabled_month = false,
        ratelimit_enabled_year = false

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
      trace_id = trace_bytes,
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

  it("extract rate limit payload info properly", function()
    local payload = analytics:create_payload(request_log_rate_limit)
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
        header_content_type = "application/json",
        header_ratelimit_limit = 10,
        header_ratelimit_remaining = 0,
        header_ratelimit_reset = 39,
        header_retry_after = 39,
        header_x_ratelimit_limit_second = 5,
        header_x_ratelimit_limit_minute = 10,
        header_x_ratelimit_limit_hour = 500,
        header_x_ratelimit_limit_day = 600,
        header_x_ratelimit_limit_month = 700,
        header_x_ratelimit_limit_year = 800,
        header_x_ratelimit_remaining_second = 5,
        header_x_ratelimit_remaining_minute = 0,
        header_x_ratelimit_remaining_hour = 480,
        header_x_ratelimit_remaining_day = 580,
        header_x_ratelimit_remaining_month = 680,
        header_x_ratelimit_remaining_year = 780,
        ratelimit_enabled = true,
        ratelimit_enabled_second = true,
        ratelimit_enabled_minute = true,
        ratelimit_enabled_hour = true,
        ratelimit_enabled_day = true,
        ratelimit_enabled_month = true,
        ratelimit_enabled_year = true
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
      trace_id = trace_bytes,
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
    local payload = analytics:create_payload(request_log_rate_limit)
    local bytes = pb.encode("kong.model.analytics.RequestMetadata", payload)
    local decoded = pb.decode("kong.model.analytics.RequestMetadata", bytes)
    assert.are.same(payload, decoded)
  end)

  it("encode strings to integers correctly", function()
    local request_log_with_strings = {
      response = {
        headers = {
          ["content-length"] = "41",
          ['ratelimit-limit'] = "10",
          ['ratelimit-remaining'] = "0",
          ['ratelimit-reset'] = "39",
          ['retry-after'] = "39",
          ['x-ratelimit-limit-minute'] = "10",
          ['x-ratelimit-remaining-minute'] = "0",
        }
      }
    }
    local payload = analytics:create_payload(request_log_with_strings)
    local bytes = pb.encode("kong.model.analytics.RequestMetadata", payload)
    local decoded = pb.decode("kong.model.analytics.RequestMetadata", bytes)
    local expected = {
      client_ip = "",
      started_at = 0,
      trace_id = "",
      response = {
        http_status = 0,
        body_size = 0,
        header_content_length = 41,
        header_content_type = "",
        header_ratelimit_limit = 10,
        header_ratelimit_remaining = 0,
        header_ratelimit_reset = 39,
        header_retry_after = 39,
        header_x_ratelimit_limit_second = 0,
        header_x_ratelimit_limit_minute = 10,
        header_x_ratelimit_limit_hour = 0,
        header_x_ratelimit_limit_day = 0,
        header_x_ratelimit_limit_month = 0,
        header_x_ratelimit_limit_year = 0,
        header_x_ratelimit_remaining_second = 0,
        header_x_ratelimit_remaining_minute = 0,
        header_x_ratelimit_remaining_hour = 0,
        header_x_ratelimit_remaining_day = 0,
        header_x_ratelimit_remaining_month = 0,
        header_x_ratelimit_remaining_year = 0,
        ratelimit_enabled = true,
        ratelimit_enabled_second = false,
        ratelimit_enabled_minute = true,
        ratelimit_enabled_hour = false,
        ratelimit_enabled_day = false,
        ratelimit_enabled_month = false,
        ratelimit_enabled_year = false
      },
      tries = {},
    }
    assert.are.same(expected, decoded)
  end)

  it("encode and decode defaults correctly", function()
    local payload = analytics:create_payload({})
    local bytes = pb.encode("kong.model.analytics.RequestMetadata", payload)
    local decoded = pb.decode("kong.model.analytics.RequestMetadata", bytes)
    local default = {
      client_ip = "",
      started_at = 0,
      trace_id = "",
      response = {
        http_status = 0,
        body_size = 0,
        header_content_length = 0,
        header_content_type = "",
        header_ratelimit_limit = 0,
        header_ratelimit_remaining = 0,
        header_ratelimit_reset = 0,
        header_retry_after = 0,
        header_x_ratelimit_limit_second = 0,
        header_x_ratelimit_limit_minute = 0,
        header_x_ratelimit_limit_hour = 0,
        header_x_ratelimit_limit_day = 0,
        header_x_ratelimit_limit_month = 0,
        header_x_ratelimit_limit_year = 0,
        header_x_ratelimit_remaining_second = 0,
        header_x_ratelimit_remaining_minute = 0,
        header_x_ratelimit_remaining_hour = 0,
        header_x_ratelimit_remaining_day = 0,
        header_x_ratelimit_remaining_month = 0,
        header_x_ratelimit_remaining_year = 0,
        ratelimit_enabled = false,
        ratelimit_enabled_second = false,
        ratelimit_enabled_minute = false,
        ratelimit_enabled_hour = false,
        ratelimit_enabled_day = false,
        ratelimit_enabled_month = false,
        ratelimit_enabled_year = false
      },
      tries = {},
    }
    assert.are.same(default, decoded)
  end)
end)
