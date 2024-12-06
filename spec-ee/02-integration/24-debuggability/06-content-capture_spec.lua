-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local helpers = require "spec.helpers"
local debug_spec_helpers = require "spec-ee/02-integration/24-debuggability/helpers"
local http_mock = require "spec.helpers.http_mock"
local gzip = require "kong.tools.gzip"
local cjson = require "cjson.safe"
local kong_table = require "kong.tools.table"
local inspect = require "inspect"

local table_merge = kong_table.table_merge
local table_contains = kong_table.table_contains

local TIMEOUT = 10
local TCP_PORT = helpers.get_available_port()

local setup_analytics_sink = debug_spec_helpers.setup_analytics_sink
local teardown_analytics_sink = debug_spec_helpers.teardown_analytics_sink
local assert_valid_trace = debug_spec_helpers.assert_valid_trace
local assert_produces_trace = debug_spec_helpers.assert_produces_trace
local assert_dp_logged = debug_spec_helpers.assert_dp_logged
local assert_session_started = debug_spec_helpers.assert_session_started
local teardown_kong = debug_spec_helpers.teardown_kong
local post_updates = debug_spec_helpers.post_updates
local setup_kong = debug_spec_helpers.setup_kong
local clean_logfiles = debug_spec_helpers.clean_logfiles


local function start_session(session_opts)
  local proxy_client = helpers.proxy_client(10000, 9002)
  setup_analytics_sink(TCP_PORT)
  local updates_start = {
    sessions = {
      table_merge(session_opts or {}, {
        id = "session_id_1",
        action = "START",
        duration = 100,
        max_samples = 100,
      })
    }
  }
  post_updates(proxy_client, updates_start)
  -- verify session started
  assert_session_started("session_id_1", true, TIMEOUT)
  proxy_client:close()
end

local function stop_session()
  local proxy_client = helpers.proxy_client(10000, 9002)
  local updates_stop = {
    sessions = {
      {
        id = "session_id_1",
        action = "STOP",
      }
    }
  }
  post_updates(proxy_client, updates_stop)
  -- verify session stopped
  assert_dp_logged("debug session session_id_1 stopped", true, TIMEOUT)
  clean_logfiles()
  proxy_client:close()
end

describe("Active Tracing #content_capture", function()
  local proxy_client
  local capture_endpoint_port, capture_server

  lazy_setup(function()
    capture_endpoint_port = helpers.get_available_port()
    capture_server = assert(http_mock.new(capture_endpoint_port, {
      ["/cmek"] = {
        access = [[
            local cjson = require "cjson"
            ngx.req.read_body()
            local echo = ngx.req.get_body_data()
            ngx.status = 200
            ngx.say(echo)
          ]]
      }
    }, {
      tls = true,
      log_opts = {
        resp = true,
        resp_body = true
      }
    }))
    assert(capture_server:start())

    setup_kong(nil, {
      cluster_cmek_endpoint = "localhost:" .. capture_endpoint_port .. "/cmek",
      -- this is the crt used by the mock http server when tls == true
      lua_ssl_trusted_certificate = "spec/fixtures/kong_spec.crt",
    }, nil)

    proxy_client = helpers.proxy_client(10000, 9002)
  end)

  after_each(function()
    teardown_analytics_sink(TCP_PORT)
  end)

  lazy_teardown(function()
    if proxy_client then
      proxy_client:close()
    end
    teardown_kong()
    capture_server:stop()
  end)

  for _, captures in ipairs({
    { },
    { "body" },
    { "headers" },
    { "body",    "headers" },
    { "headers", "body" },
  }) do
    it("captures and reports " .. inspect(captures), function()
      start_session({
        capture_content = table.concat(captures, ","),
      })
      finally(function()
        stop_session()
      end)

      local test_body = "Hello! Btw my credit card number is 4242-4242-4242-4242!"
      local redacted_body = "Hello! Btw my credit card number is *******************!"
      local test_host = "localhost"
      local test_content_type = "text/plain"
      local test_header_foo = "bar"
      local trace = assert_produces_trace(function()
        return assert(proxy_client:send {
          headers = {
            ["host"] = test_host,
            ["Content-Type"] = test_content_type,
            ["foo"] = test_header_foo,
          },
          method = "POST",
          path = "/sampled",
          body = test_body,
        })
      end, TCP_PORT, 200)
      assert_valid_trace(trace)

      -- when captures are empty, no content is exported
      if #captures == 0 then
        assert.error(function()
          capture_server.eventually:has_request()
        end)
        return
      end

      capture_server.eventually:has_response_satisfy(function(resp)
        -- get the compressed content
        local gzipped = assert(resp.body)
        local body, err = gzip.inflate_gzip(gzipped)
        assert.is_nil(err)
        assert.is_string(body)

        -- iterate through items (there is only one)
        local contents = cjson.decode(body)
        assert.is_table(contents)
        for _, content in ipairs(contents) do
          assert.is_table(content)
          for k, v in pairs(content) do
            -- the key is a trace_id followed by ":reqres"
            assert.is_truthy(k:match("%x+:reqres"))

            -- assert valid body
            if table_contains(captures, "body") then
              assert.same(redacted_body, v.request_body)
              assert.is_string(v.response_body)
            end

            -- assert valid headers
            if table_contains(captures, "headers") then
              assert.is_table(v.request_headers)
              assert.equals(v.request_headers.host, test_host)
              assert.equals(v.request_headers["content-type"], test_content_type)
              assert.equals(v.request_headers.foo, test_header_foo)
              assert.is_table(v.response_headers)
              assert.equals(v.response_headers["content-type"], "application/json")
              assert.equals(v.response_headers["x-powered-by"], "mock_upstream")
            end
          end
        end
      end)
    end)
  end

  for _, unsupported_content_type in ipairs({
    "application/octet-stream",
    "audio/aac",
    "application",
  }) do
    it("does not report bodies with #unsupported content type: " .. unsupported_content_type, function()
      local captures = { "body" }
      start_session({
        capture_content = table.concat(captures, ","),
      })
      finally(function()
        stop_session()
      end)

      local test_body = "Hello!!"
      local test_host = "localhost"
      local trace = assert_produces_trace(function()
        return assert(proxy_client:send {
          headers = {
            ["host"] = test_host,
            ["Content-Type"] = unsupported_content_type,
          },
          method = "POST",
          path = "/sampled",
          body = test_body,
        })
      end, TCP_PORT, 200)
      assert_valid_trace(trace)

      capture_server.eventually:has_response_satisfy(function(resp)
        local gzipped = assert(resp.body)
        local body, err = gzip.inflate_gzip(gzipped)
        assert.is_nil(err)
        assert.is_string(body)

        local contents = cjson.decode(body)
        assert.is_table(contents)
        for _, content in ipairs(contents) do
          assert.is_table(content)
          for k, v in pairs(content) do
            assert.is_truthy(k:match("%x+:reqres"))

            if table_contains(captures, "body") then
              -- nil due to invalid content type
              assert.is_nil(v.request_body)
              assert.is_string(v.response_body)
            end
          end
        end
      end)
      assert_dp_logged("unsupported content-type: " .. unsupported_content_type, true)
    end)
  end

  it("does not report bodies that #exceed the maximum allowed size", function()
    local captures = { "body" }
    start_session({
      capture_content = table.concat(captures, ","),
    })
    finally(function()
      stop_session()
    end)

    local test_body = string.rep("a", 129 * 1e3)
    local test_host = "localhost"
    local test_content_type = "text/plain"
    local trace = assert_produces_trace(function()
      return assert(proxy_client:send {
        headers = {
          ["host"] = test_host,
          ["Content-Type"] = test_content_type,
        },
        method = "POST",
        path = "/sampled",
        body = test_body,
      })
    end, TCP_PORT, 200)
    assert_valid_trace(trace)

    assert.error(function()
      capture_server.eventually:has_request()
    end)
    assert_dp_logged("request body file too big", true)
    assert_dp_logged("body size: \\d+ exceeds limit", false)
  end)
end)
