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
local deep_copy = require("kong.tools.table").deep_copy
local protoc = require "protoc"
local pb = require "pb"
local analytics = require "kong.analytics"
local to_hex = require "resty.string".to_hex
local tracing_context = require "kong.observability.tracing.tracing_context"
local at_instrum = require "kong.enterprise_edition.debug_session.instrumentation"

local orig_ngx_var_mt = getmetatable(ngx.var)
local orig_ngx_header = ngx.header
local orig_ngx_get_phase = ngx.get_phase
local request_id_value = to_hex(utils.get_rand_bytes(16))
local table_sort = table.sort

local CONTENT_TYPE = "application/json"
local CONTENT_LENGTH = 503

local request_log = {
  auth_type = "key-auth",
  authenticated_entity = {
    id = "4135aa9dc1b842a653dea846903ddb95bfb8c5a10c504a7fa16e10bc31d1fdf0",
    consumer_id = ""
  },
  latencies = {
    request = 515,
    kong = 58,
    proxy = 457,
    receive = 0,
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
      ['content-type'] = CONTENT_TYPE,
      date = "Thu, 25 Feb 2021 05=57=48 GMT",
      connection = "close",
      ['access-control-allow-credentials'] = "true",
      ['content-length'] = CONTENT_LENGTH,
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
    tags = {
      "cluster_id:167290ee-c682-4ebf-bdea-777777777777"
    },
    service = {
      id = "167290ee-c682-4ebf-bdea-e49a3ac5e260"
    }
  },
  consumer = {
    id = "54baa5a9-23d6-41e0-9c9a-02434b010b25",
  },
  started_at = 1614232668342,
  upstream_status = "200",
  source = "upstream",
  application_context = {
    application_id = "app_id",
    portal_id = "p_id",
    organization_id = "org_id",
    developer_id = "dev_id",
    product_version_id = "pv_id",
    authorization_scope_id = "as_id",
  },
  consumer_groups = {
    { name = "c_group1" },
  },
  ai = {
    ["ai-proxy"] = {
      meta = {
        plugin_id = '6e7c40f6-ce96-48e4-a366-d109c169e444',
        provider_name = 'openai',
        request_model = 'gpt-3.5-turbo',
        response_model = 'gpt-3.5-turbo-0613',
        llm_latency = 3402,
      },
      usage = {
        prompt_tokens = 0,
        completion_tokens = 0,
        total_tokens = 0,
        cost = 0,
        time_per_token = 136,
      },
      cache = {
        embeddings_model = "text-embedding-3-small",
        cache_status = "Hit",
        fetch_latency = 452,
        embeddings_latency = 424,
        embeddings_provider = "openai",
        embeddings_tokens = 10,
        cost_caching = 0.0020,
      }
    },
    ["ai-request-transformer"] = {
      meta = {
        plugin_id = 'da587462-a802-4c22-931a-e6a92c5866d1',
        provider_name = 'cohere',
        request_model = 'command',
        response_model = 'command',
        llm_latency = 3402,
      },
      usage = {
        prompt_tokens = 40,
        completion_tokens = 25,
        total_tokens = 65,
        cost = 0.00057,
        time_per_token = 136,
      },
      cache = {
        embeddings_model = "text-embedding-3-small",
        cache_status = "Hit",
        fetch_latency = 452,
        embeddings_latency = 424,
        embeddings_provider = "openai",
        embeddings_tokens = 10,
        cost_caching = 0.0020,
      },
    },
  },
  threats = {
    injection = {
      name = "sql",
      location = "body",
      details = "sql injection",
      action = "blocked",
    },
  },
}

local resp_hdr_mt = {
  __index = function(t, k)
    if type(k) ~= "string" then
      error("invalid key type: " .. type(k))
    end

    k = k:lower():gsub("_", "-")

    return rawget(t, k)
  end,

  __newindex = function(t, k, v)
    if type(k) ~= "string" then
      error("invalid key type: " .. type(k))
    end

    k = k:lower():gsub("_", "-")

    rawset(t, k, v)
  end,
}

local function compare_tables(a, b)
  return a.plugin_name < b.plugin_name
end

local function set_context(trace_bytes, ngx_var, resp_hdrs, rl_ctx)
  if trace_bytes then
    tracing_context.set_raw_trace_id(trace_bytes)
    _G.ngx.ctx["KONG_SPANS"] = {{
      should_sample = true
    }}
    stub(at_instrum, "get_root_span").returns({
      trace_id = trace_bytes,
    })
  else
    stub(at_instrum, "get_root_span").returns(nil)
  end

  setmetatable(_G.ngx.var, nil)
  for k, v in pairs(ngx_var or {}) do
    _G.ngx.var[k] = v
  end

  _G.ngx.header = setmetatable(deep_copy(resp_hdrs or {}), resp_hdr_mt)

  _G.ngx.ctx.__rate_limiting_context__ = deep_copy(rl_ctx)

  _G.ngx.get_phase = function() -- luacheck: ignore
    return "access"
  end

  _G.kong.log = {
    notice = function() end,
    info = function() end,
  }

  _G.kong.ctx = {
    shared = {
      kaa_application_context = {
        application_id = "app_id",
        portal_id = "p_id",
        organization_id = "org_id",
        developer_id = "dev_id",
        product_version_id = "pv_id",
        authorization_scope_id = "as_id",
      },
    }
  }

  _G.kong.client = {
    get_consumer_groups = function()
      return {
        { id = "1" },
      }
    end
  }

  -- make sure to reload the module
  package.loaded["kong.observability.tracing.request_id"] = nil
  package.loaded["kong.analytics"] = nil
  analytics = require("kong.analytics")
end


local function reset_context()
  _G.ngx.ctx.KONG_SPANS = nil
  tracing_context.set_raw_trace_id(nil)
  _G.ngx.ctx.__rate_limiting_context__ = nil
  setmetatable(_G.ngx.var, orig_ngx_var_mt)
  _G.ngx.header = orig_ngx_header
  _G.ngx.get_phase = orig_ngx_get_phase
  at_instrum.get_root_span:revert()
end


describe("extract request log properly", function()
  local trace_bytes = utils.get_rand_bytes(16)

  lazy_teardown(function()
    reset_context()
  end)

  it("extract payload info properly dont sample trace_id", function()
    set_context(
      trace_bytes,
      {
        kong_request_id = request_id_value,
        http_user_agent = "HTTPie/2.4.0",
        http_host = "localhost:8000",
      },
      {
        content_type = CONTENT_TYPE,
        content_length = CONTENT_LENGTH,
      },
      nil
    )
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
        header_content_length = CONTENT_LENGTH,
        header_content_type = CONTENT_TYPE,
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
        name = "route",
        control_plane_id = "167290ee-c682-4ebf-bdea-777777777777"
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
        response_ms = 515,
        receive_ms = 0,
      },
      trace_id = "",
      active_tracing_trace_id = trace_bytes,
      request_id = request_id_value,
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
      upstream_status = "200",
      source = "upstream",
      application_context = {
        application_id = "app_id",
        portal_id = "p_id",
        organization_id = "org_id",
        developer_id = "dev_id",
        product_version_id = "pv_id",
        authorization_scope_id = "as_id",
      },
      consumer_groups = {
        { id = "1" },
      },
      websocket = false,
      sse = false,
      ai = {
        {
          plugin_name = "ai-proxy",
          meta = {
            plugin_id = '6e7c40f6-ce96-48e4-a366-d109c169e444',
            provider_name = 'openai',
            request_model = 'gpt-3.5-turbo',
            response_model = 'gpt-3.5-turbo-0613',
            llm_latency = 3402,
          },
          usage = {
            prompt_tokens = 0,
            completion_tokens = 0,
            total_tokens = 0,
            cost = 0,
            time_per_token = 136,
          },
          cache = {
            embeddings_model = "text-embedding-3-small",
            cache_status = "Hit",
            fetch_latency = 452,
            embeddings_latency = 424,
            embeddings_provider = "openai",
            embeddings_tokens = 10,
            cost_caching = 0.0020,
          }
        },
        {
          plugin_name = "ai-request-transformer",
          meta = {
            plugin_id = 'da587462-a802-4c22-931a-e6a92c5866d1',
            provider_name = 'cohere',
            request_model = 'command',
            response_model = 'command',
            llm_latency = 3402,
          },
          usage = {
            prompt_tokens = 40,
            completion_tokens = 25,
            total_tokens = 65,
            cost = 0.00057,
            time_per_token = 136,
          },
          cache = {
            embeddings_model = "text-embedding-3-small",
            cache_status = "Hit",
            fetch_latency = 452,
            embeddings_latency = 424,
            embeddings_provider = "openai",
            embeddings_tokens = 10,
            cost_caching = 0.0020,
          },

        }
      },
      threats = {
        injection = {
          name = "sql",
          location = "body",
          details = "sql injection",
          action = "blocked",
        },
      },
    }

    table_sort(expected.ai, compare_tables)
    table_sort(payload.ai, compare_tables)
    assert.are.same(expected, payload)
  end)

  it("extract payload info properly", function()
    set_context(
      trace_bytes,
      {
        kong_request_id = request_id_value,
        http_user_agent = "HTTPie/2.4.0",
        http_host = "localhost:8000",
      },
      {
        content_type = CONTENT_TYPE,
        content_length = CONTENT_LENGTH,
      },
      nil
    )
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
        name = "route",
        control_plane_id = "167290ee-c682-4ebf-bdea-777777777777"
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
        response_ms = 515,
        receive_ms = 0,
      },
      trace_id = trace_bytes,
      active_tracing_trace_id = trace_bytes,
      request_id = request_id_value,
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
      upstream_status = "200",
      source = "upstream",
      application_context = {
        application_id = "app_id",
        portal_id = "p_id",
        organization_id = "org_id",
        developer_id = "dev_id",
        product_version_id = "pv_id",
        authorization_scope_id = "as_id",
      },
      consumer_groups = {
        { id = "1" },
      },
      websocket = false,
      sse = false,
      ai = {
        {
          plugin_name = "ai-proxy",
          meta = {
            plugin_id = '6e7c40f6-ce96-48e4-a366-d109c169e444',
            provider_name = 'openai',
            request_model = 'gpt-3.5-turbo',
            response_model = 'gpt-3.5-turbo-0613',
            llm_latency = 3402,
          },
          usage = {
            prompt_tokens = 0,
            completion_tokens = 0,
            total_tokens = 0,
            cost = 0,
            time_per_token = 136,
          },
          cache = {
            embeddings_model = "text-embedding-3-small",
            cache_status = "Hit",
            fetch_latency = 452,
            embeddings_latency = 424,
            embeddings_provider = "openai",
            embeddings_tokens = 10,
            cost_caching = 0.0020,
          }
        },
        {
          plugin_name = "ai-request-transformer",
          meta = {
            plugin_id = 'da587462-a802-4c22-931a-e6a92c5866d1',
            provider_name = 'cohere',
            request_model = 'command',
            response_model = 'command',
            llm_latency = 3402,
          },
          usage = {
            prompt_tokens = 40,
            completion_tokens = 25,
            total_tokens = 65,
            cost = 0.00057,
            time_per_token = 136,
          },
          cache = {
            embeddings_model = "text-embedding-3-small",
            cache_status = "Hit",
            fetch_latency = 452,
            embeddings_latency = 424,
            embeddings_provider = "openai",
            embeddings_tokens = 10,
            cost_caching = 0.0020,
          },
        }
      },
      threats = {
        injection = {
          name = "sql",
          location = "body",
          details = "sql injection",
          action = "blocked",
        },
      },
    }

    table_sort(expected.ai, compare_tables)
    table_sort(payload.ai, compare_tables)
    assert.are.same(expected, payload)
  end)

  it("extract rate limit payload info properly", function()
    set_context(
      trace_bytes,
      {
        kong_request_id = request_id_value,
        http_user_agent = "HTTPie/2.4.0",
        http_host = "localhost:8000",
      },
      {
        content_type = CONTENT_TYPE,
        content_length = CONTENT_LENGTH,
      },
      {
        ['RateLimit-Limit'] = 10,
        ['RateLimit-Remaining'] = 0,
        ['RateLimit-Reset'] = 39,
        ['Retry-After'] = 39,
        ['X-RateLimit-Limit-Day'] = 600,
        ['X-RateLimit-Limit-Hour'] = 500,
        ['X-RateLimit-Limit-Minute'] = 10,
        ['X-RateLimit-Limit-Month'] = 700,
        ['X-RateLimit-Limit-Second'] = 5,
        ['X-RateLimit-Limit-Year'] = 800,
        ['X-RateLimit-Remaining-Day'] = 580,
        ['X-RateLimit-Remaining-Hour'] = 480,
        ['X-RateLimit-Remaining-Minute'] = 0,
        ['X-RateLimit-Remaining-Month'] = 680,
        ['X-RateLimit-Remaining-Second'] = 5,
        ['X-RateLimit-Remaining-Year'] = 780,
      }
    )
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
        name = "route",
        control_plane_id = "167290ee-c682-4ebf-bdea-777777777777"
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
        response_ms = 515,
        receive_ms = 0,
      },
      trace_id = trace_bytes,
      active_tracing_trace_id = trace_bytes,
      request_id = request_id_value,
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
      upstream_status = "200",
      source = "upstream",
      application_context = {
        application_id = "app_id",
        portal_id = "p_id",
        organization_id = "org_id",
        developer_id = "dev_id",
        product_version_id = "pv_id",
        authorization_scope_id = "as_id",
      },
      consumer_groups = {
        { id = "1" },
      },
      websocket = false,
      sse = false,
      ai = {
        {
          plugin_name = "ai-proxy",
          meta = {
            plugin_id = '6e7c40f6-ce96-48e4-a366-d109c169e444',
            provider_name = 'openai',
            request_model = 'gpt-3.5-turbo',
            response_model = 'gpt-3.5-turbo-0613',
            llm_latency = 3402,
          },
          usage = {
            prompt_tokens = 0,
            completion_tokens = 0,
            total_tokens = 0,
            cost = 0,
            time_per_token = 136,
          },
          cache = {
            embeddings_model = "text-embedding-3-small",
            cache_status = "Hit",
            fetch_latency = 452,
            embeddings_latency = 424,
            embeddings_provider = "openai",
            embeddings_tokens = 10,
            cost_caching = 0.0020,
          }
        },
        {
          plugin_name = "ai-request-transformer",
          meta = {
            plugin_id = 'da587462-a802-4c22-931a-e6a92c5866d1',
            provider_name = 'cohere',
            request_model = 'command',
            response_model = 'command',
            llm_latency = 3402,
          },
          usage = {
            prompt_tokens = 40,
            completion_tokens = 25,
            total_tokens = 65,
            cost = 0.00057,
            time_per_token = 136,
          },
          cache = {
            embeddings_model = "text-embedding-3-small",
            cache_status = "Hit",
            fetch_latency = 452,
            embeddings_latency = 424,
            embeddings_provider = "openai",
            embeddings_tokens = 10,
            cost_caching = 0.0020,
          },
        }
      },
      threats = {
        injection = {
          name = "sql",
          location = "body",
          details = "sql injection",
          action = "blocked",
        },
      },
    }

    table_sort(expected.ai, compare_tables)
    table_sort(payload.ai, compare_tables)
    assert.are.same(expected, payload)
  end)

  describe("WebSocket requests", function()
    it("aren't detected by default", function()
      local payload = analytics:create_payload(request_log)
      assert.is_false(payload.websocket)
    end)

    it("are detected by upgrade/connection response headers", function()
      set_context(
        nil,
        nil,
        {
          connection = "upgrade",
          upgrade = "websocket",
        },
        nil
      )

      local payload = analytics:create_payload(request_log)
      assert.is_true(payload.websocket)
    end)

    it("are detected by upgrade/connection response headers (case insensitive)", function()
      set_context(
        nil,
        nil,
        {
          connection = "Upgrade",
          upgrade = "Websocket",
        },
        nil
      )

      local payload = analytics:create_payload(request_log)
      assert.is_true(payload.websocket)
    end)
  end)

  describe("Server-Sent Events / SSE", function()
    it("aren't detected by default", function()
      local payload = analytics:create_payload(request_log)
      assert.is_false(payload.sse)
    end)

    it("are detected by the content-type response header", function()
      set_context(
        nil,
        nil,
        {
          content_type = "text/event-stream",
        },
        nil
      )

      local payload = analytics:create_payload(request_log)
      assert.is_true(payload.sse)
    end)
  end)

  it("records receive time if available", function()
    local input = deep_copy(request_log)
    input.latencies = {
      kong = 10,
      proxy = 5,
      request = 20,
      receive = 4,
    }

    local payload = analytics:create_payload(input)
    assert.equals(4, payload.latencies.receive_ms)
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
  lazy_teardown(function()
    reset_context()
  end)

  local p = protoc.new()
  p:addpath("kong/include/kong/model/analytics")
  p:loadfile("payload.proto")

  it("encode and decode data correctly", function()
    set_context(
      nil,
      {
        kong_request_id = request_id_value,
      },
      {
        content_type = CONTENT_TYPE,
        content_length = CONTENT_LENGTH,
      },
      {
        ['RateLimit-Limit'] = 10,
        ['RateLimit-Remaining'] = 0,
        ['RateLimit-Reset'] = 39,
        ['Retry-After'] = 39,
        ['X-RateLimit-Limit-Day'] = 600,
        ['X-RateLimit-Limit-Hour'] = 500,
        ['X-RateLimit-Limit-Minute'] = 10,
        ['X-RateLimit-Limit-Month'] = 700,
        ['X-RateLimit-Limit-Second'] = 5,
        ['X-RateLimit-Limit-Year'] = 800,
        ['X-RateLimit-Remaining-Day'] = 580,
        ['X-RateLimit-Remaining-Hour'] = 480,
        ['X-RateLimit-Remaining-Minute'] = 0,
        ['X-RateLimit-Remaining-Month'] = 680,
        ['X-RateLimit-Remaining-Second'] = 5,
        ['X-RateLimit-Remaining-Year'] = 780,
      }
    )
    local payload = analytics:create_payload(request_log)
    local bytes = pb.encode("kong.model.analytics.RequestMetadata", payload)
    local decoded = pb.decode("kong.model.analytics.RequestMetadata", bytes)
    assert.are.same(payload, decoded)
  end)

  it("encode strings to integers correctly", function()
    set_context(
      nil,
      {
        kong_request_id = request_id_value,
      },
      {
        content_length = CONTENT_LENGTH,
      },
      {
        ['RateLimit-Limit'] = 10,
        ['RateLimit-Remaining'] = 0,
        ['RateLimit-Reset'] = 39,
        ['Retry-After'] = 39,
        ['X-RateLimit-Limit-Minute'] = 10,
      }
    )

    local payload = analytics:create_payload({
      response = {}
    })
    local bytes = pb.encode("kong.model.analytics.Payload", { data = {payload} })
    local decoded = pb.decode("kong.model.analytics.Payload", bytes)
    local expected = {
      auth = {
        id = "",
        type = "",
      },
      client_ip = "",
      started_at = 0,
      trace_id = "",
      active_tracing_trace_id = "",
      request_id = request_id_value,
      request = {
        body_size = 0,
        header_host = "",
        header_user_agent = "",
        http_method = "",
        uri = "",
      },
      response = {
        http_status = 0,
        body_size = 0,
        header_content_length = CONTENT_LENGTH,
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
      upstream = {
        upstream_uri = "",
      },
      upstream_status = "",
      service = {
        id = "",
        name = "",
        port = 0,
        protocol = "",
      },
      route = {
        id = "",
        name = "",
        control_plane_id = ""
      },
      source = "",
      application_context = {
        application_id = "app_id",
        portal_id = "p_id",
        organization_id = "org_id",
        developer_id = "dev_id",
        product_version_id = "pv_id",
        authorization_scope_id = "as_id",
      },
      consumer = {
        id = "",
      },
      consumer_groups = {
        { id = "1" },
      },
      latencies = {
        kong_gateway_ms = 0,
        receive_ms = 0,
        response_ms = 0,
        upstream_ms = 0,
      },
      websocket = false,
      sse = false,
      ai = {},
      threats = {},
    }
    assert.are.same(expected, decoded.data[1])
  end)

  it("encode and decode defaults correctly", function()
    local payload = analytics:create_payload({})
    local bytes = pb.encode("kong.model.analytics.RequestMetadata", payload)
    local decoded = pb.decode("kong.model.analytics.RequestMetadata", bytes)
    local default = {
      auth = {
        id = "",
        type = "",
      },
      client_ip = "",
      started_at = 0,
      trace_id = "",
      active_tracing_trace_id = "",
      request_id = request_id_value,
      request = {
        body_size = 0,
        header_host = "",
        header_user_agent = "",
        http_method = "",
        uri = "",
      },
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
      upstream = {
        upstream_uri = "",
      },
      upstream_status = "",
      service = {
        id = "",
        name = "",
        port = 0,
        protocol = "",
      },
      route = {
        id = "",
        name = "",
        control_plane_id = "",
      },
      source = "",
      application_context = {
        application_id = "app_id",
        portal_id = "p_id",
        organization_id = "org_id",
        developer_id = "dev_id",
        product_version_id = "pv_id",
        authorization_scope_id = "as_id",
      },
      consumer = {
        id = "",
      },
      consumer_groups = {
        { id = "1" },
      },
      latencies = {
        kong_gateway_ms = 0,
        receive_ms = 0,
        response_ms = 0,
        upstream_ms = 0,
      },
      websocket = false,
      sse = false,
      ai = {},
      threats = {},
    }
    assert.are.same(default, decoded)
  end)
end)
