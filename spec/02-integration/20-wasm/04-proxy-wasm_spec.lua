local helpers = require "spec.helpers"
local cjson = require "cjson"
local meta = require "kong.meta"


local HEADER_NAME_PHASE = "X-PW-Phase"
local HEADER_NAME_TEST = "X-PW-Test"
local HEADER_NAME_INPUT = "X-PW-Input"
local HEADER_NAME_DISPATCH_ECHO = "X-PW-Dispatch-Echo"
local HEADER_NAME_ADD_REQ_HEADER = "X-PW-Add-Header"
local HEADER_NAME_ADD_RESP_HEADER = "X-PW-Add-Resp-Header"
local HEADER_NAME_LUA_PROPERTY = "X-Lua-Property"
local HEADER_NAME_LUA_VALUE = "X-Lua-Value"
local UUID_PATTERN = "%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x"

local DNS_HOSTNAME = "wasm.test"
local MOCK_UPSTREAM_DNS_ADDR = DNS_HOSTNAME .. ":" .. helpers.mock_upstream_port

for _, strategy in helpers.each_strategy({ "postgres", "off" }) do

describe("proxy-wasm filters (#wasm) (#" .. strategy .. ")", function()
  local r_single, mock_service
  local hosts_file

  lazy_setup(function()
    require("kong.runloop.wasm").enable({
      { name = "tests",
        path = helpers.test_conf.wasm_filters_path .. "/tests.wasm",
      },
    })

    local bp = helpers.get_db_utils(strategy, {
      "routes",
      "services",
      "filter_chains",
    })

    mock_service = assert(bp.services:insert {
      host = helpers.mock_upstream_host,
      port = helpers.mock_upstream_port,
    })

    local mock_upstream = assert(bp.upstreams:insert {
      name = "mock_upstream",
    })

    assert(bp.targets:insert {
      upstream = { id = mock_upstream.id },
      target = helpers.mock_upstream_host .. ":" .. helpers.mock_upstream_port,
    })

    r_single = assert(bp.routes:insert {
      paths = { "/single" },
      strip_path = true,
      service = mock_service,
    })

    local r_double = assert(bp.routes:insert {
      paths = { "/double" },
      strip_path = true,
      service = mock_service,
    })

    assert(bp.filter_chains:insert {
      route = r_single,
      filters = {
        { name = "tests" },
      },
    })

    assert(bp.filter_chains:insert {
      route = r_double,
      filters = {
        { name = "tests" },
        { name = "tests" },
      },
    })

    local r_lua = assert(bp.routes:insert {
      paths = { "/lua" },
      strip_path = true,
      service = mock_service,
    })

    assert(bp.filter_chains:insert {
      route = r_lua,
      filters = {
        { name = "tests" },
      },
    })

    assert(bp.plugins:insert {
      name = "pre-function",
      config = {
        access = {([[
          local property = kong.request.get_header(%q)

          if property then
            local value = kong.request.get_header(%q)
            kong.log.notice("Setting kong.ctx.shared.", property, " to '", value, "'")
            kong.ctx.shared[property] = value
          end
          ]]):format(HEADER_NAME_LUA_PROPERTY, HEADER_NAME_LUA_VALUE)
        },
      },
    })

    assert(bp.plugins:insert {
      name = "post-function",
      config = {
        header_filter = {([[
          local property = kong.request.get_header(%q)
          if property then
            local value = kong.ctx.shared[property]
            local header = %q

            if value then
              kong.log.notice("Setting ", header, " response header to '", value, "'")
              kong.response.set_header(header, value)
            else
              kong.log.notice("Clearing ", header, " response header")
              kong.response.clear_header(header)
            end
          end
          ]]):format(HEADER_NAME_LUA_PROPERTY, HEADER_NAME_LUA_VALUE)
        },
      },
    })


    -- XXX our dns mock fixture doesn't work when called from wasm land
    hosts_file = os.tmpname()
    assert(helpers.file.write(hosts_file,
                              "127.0.0.1 " .. DNS_HOSTNAME .. "\n"))

    assert(helpers.start_kong({
      database = strategy,
      nginx_conf = "spec/fixtures/custom_nginx.template",
      wasm = true,
      dns_hostsfile = hosts_file,
      resolver_hosts_file = hosts_file,
      plugins = "pre-function,post-function",
    }))
  end)

  lazy_teardown(function()
    helpers.stop_kong()
    os.remove(hosts_file)
  end)

  before_each(function()
    helpers.clean_logfile()
  end)

  describe("runs a filter chain", function()
    it("with a single filter", function()
      local client = helpers.proxy_client()
      finally(function() client:close() end)

      local res = assert(client:send {
        method = "GET",
        path = "/single/status/200",
      })

      assert.res_status(200, res)
      assert.logfile().has.no.line("[error]", true, 0)
      assert.logfile().has.no.line("[crit]",  true, 0)
    end)

    it("with multiple filters", function()
      local client = helpers.proxy_client()
      finally(function() client:close() end)

      local res = assert(client:send {
        method = "GET",
        path = "/double/status/200",
      })

      assert.res_status(200, res)
      assert.logfile().has.no.line("[error]", true, 0)
      assert.logfile().has.no.line("[crit]",  true, 0)
    end)
  end)

  describe("filters can", function()
    it("add request headers", function()
      local client = helpers.proxy_client()
      finally(function() client:close() end)

      local res = assert(client:send {
        method = "GET",
        path = "/single/status/200",
        headers = {
          [HEADER_NAME_ADD_REQ_HEADER] = "Via=proxy-wasm",
        }
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.equal("1.1 " .. meta._SERVER_TOKENS, json.headers["via"])
      -- TODO: honor case-sensitivity (proxy-wasm-rust-sdk/ngx_wasm_module investigation)
      -- assert.equal("proxy-wasm", json.headers["Via"])
      assert.logfile().has.no.line("[error]", true, 0)
      assert.logfile().has.no.line("[crit]",  true, 0)
    end)

    it("remove request headers", function()
      local client = helpers.proxy_client()
      finally(function() client:close() end)

      local res = assert(client:send {
        method = "GET",
        path = "/single/status/200",
        headers = {
          [HEADER_NAME_ADD_REQ_HEADER] = "Via=proxy-wasm",
        }
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      -- The 'test' Rust filter removes the "X-PW-*" request headers
      assert.is_nil(json.headers[HEADER_NAME_ADD_REQ_HEADER])
      assert.logfile().has.no.line("[error]", true, 0)
      assert.logfile().has.no.line("[crit]",  true, 0)
    end)

    it("add response headers on_request_headers", function()
      local client = helpers.proxy_client()
      finally(function() client:close() end)

      local res = assert(client:send {
        method = "GET",
        path = "/single/status/200",
        headers = {
          [HEADER_NAME_ADD_RESP_HEADER] = "X-Via=proxy-wasm",
        }
      })

      assert.res_status(200, res)
      local via = assert.response(res).has.header("x-via")
      assert.equal("proxy-wasm", via)
      assert.logfile().has.line([[testing in "RequestHeaders"]])
      assert.logfile().has.no.line("[error]", true, 0)
      assert.logfile().has.no.line("[crit]",  true, 0)
    end)

    it("add response headers on_response_headers", function()
      local client = helpers.proxy_client()
      finally(function() client:close() end)

      local res = assert(client:send {
        method = "GET",
        path = "/single/status/200",
        headers = {
          [HEADER_NAME_PHASE] = "response_headers",
          [HEADER_NAME_ADD_RESP_HEADER] = "X-Via=proxy-wasm",
        }
      })

      assert.res_status(200, res)
      local via = assert.response(res).has.header("x-via")
      assert.equal("proxy-wasm", via)
      assert.logfile().has.line([[testing in "ResponseHeaders"]])
      assert.logfile().has.no.line("[error]", true, 0)
      assert.logfile().has.no.line("[crit]",  true, 0)
    end)

    -- describe+it:
    -- "filters can NOT ..."
    it("NOT add response headers on_log", function()
      local client = helpers.proxy_client()
      finally(function() client:close() end)

      local res = assert(client:send {
        method = "GET",
        path = "/single/status/200",
        headers = {
          [HEADER_NAME_PHASE] = "log",
          [HEADER_NAME_ADD_RESP_HEADER] = "X-Via=proxy-wasm",
        }
      })

      assert.res_status(200, res)
      assert.response(res).has.no.header("x-via")
      assert.logfile().has.line([[testing in "Log"]])
      assert.logfile().has.line("can only set response headers before \"on_response_body\"")
    end)

    pending("throw a trap", function()
      -- Used to work but now broken (obscure wasmtime SIGSEV), no clue
      local client = helpers.proxy_client()
      finally(function() client:close() end)

      local res = assert(client:send {
        method = "GET",
        path = "/single/status/200",
        headers = {
          [HEADER_NAME_TEST] = "trap",
        }
      })

      assert.res_status(500, res)
      assert.logfile().has.line("panicked at 'trap msg'")
      assert.logfile().has.line("trap in proxy_on_request_headers:.*?unreachable")
    end)

    pending("send a local response", function()
      local client = helpers.proxy_client()
      finally(function() client:close() end)

      local res = assert(client:send {
        method = "GET",
        path = "/single/status/201", -- status overriden by 'test' filter
        headers = {
          [HEADER_NAME_TEST] = "local_response",
          [HEADER_NAME_INPUT] = "Hello from proxy-wasm",
        }
      })

      local body = assert.res_status(200, res)
      assert.equal("Hello from proxy-wasm", body)
      assert.logfile().has.no.line("[error]", true, 0)
      assert.logfile().has.no.line("[crit]",  true, 0)
    end)

    it("read kong.client.protocol", function()
      local client = helpers.proxy_client()
      finally(function() client:close() end)

      local res = assert(client:send {
        method = "GET",
        path = "/single/status/200",
        headers = {
          [HEADER_NAME_TEST] = "get_kong_property",
          [HEADER_NAME_INPUT] = "client.protocol",
          [HEADER_NAME_DISPATCH_ECHO] = "on",
        }
      })

      local body = assert.res_status(200, res)
      assert.equal("http", body)
      assert.logfile().has.no.line("[error]", true, 0)
      assert.logfile().has.no.line("[crit]",  true, 0)
    end)

    it("read kong.nginx.subsystem", function()
      local client = helpers.proxy_client()
      finally(function() client:close() end)

      local res = assert(client:send {
        method = "GET",
        path = "/single/status/200",
        headers = {
          [HEADER_NAME_TEST] = "get_kong_property",
          [HEADER_NAME_INPUT] = "nginx.subsystem",
          [HEADER_NAME_DISPATCH_ECHO] = "on",
        }
      })

      local body = assert.res_status(200, res)
      assert.equal("http", body)
      assert.logfile().has.no.line("[error]", true, 0)
      assert.logfile().has.no.line("[crit]",  true, 0)
    end)

    it("read kong.node.id", function()
      local client = helpers.proxy_client()
      finally(function() client:close() end)

      local res = assert(client:send {
        method = "GET",
        path = "/single/status/200",
        headers = {
          [HEADER_NAME_TEST] = "get_kong_property",
          [HEADER_NAME_INPUT] = "node.id",
          [HEADER_NAME_DISPATCH_ECHO] = "on",
        }
      })

      local body = assert.res_status(200, res)
      assert.matches(UUID_PATTERN, body)
      assert.logfile().has.no.line("[error]", true, 0)
      assert.logfile().has.no.line("[crit]",  true, 0)
    end)

    it("read kong.node.memory_stats", function()
      local client = helpers.proxy_client()
      finally(function() client:close() end)

      local res = assert(client:send {
        method = "GET",
        path = "/single/status/200",
        headers = {
          [HEADER_NAME_TEST] = "get_kong_property",
          [HEADER_NAME_INPUT] = "node.memory_stats",
          [HEADER_NAME_DISPATCH_ECHO] = "on",
        }
      })

      local body = assert.res_status(200, res)
      assert.matches("{.*lua_shared_dicts.*}", body)
      assert.logfile().has.no.line("[error]", true, 0)
      assert.logfile().has.no.line("[crit]",  true, 0)
    end)

    it("read kong.request.forwarded_host", function()
      local client = helpers.proxy_client()
      finally(function() client:close() end)

      local res = assert(client:send {
        method = "GET",
        path = "/single/status/200",
        headers = {
          [HEADER_NAME_TEST] = "get_kong_property",
          [HEADER_NAME_INPUT] = "request.forwarded_host",
          [HEADER_NAME_DISPATCH_ECHO] = "on",
        }
      })

      local body = assert.res_status(200, res)
      assert.matches("^[a-z.0-9%-]+$", body)
      assert.logfile().has.no.line("[error]", true, 0)
      assert.logfile().has.no.line("[crit]",  true, 0)
    end)

    it("read kong.request.forwarded_port", function()
      local client = helpers.proxy_client()
      finally(function() client:close() end)

      local res = assert(client:send {
        method = "GET",
        path = "/single/status/200",
        headers = {
          [HEADER_NAME_TEST] = "get_kong_property",
          [HEADER_NAME_INPUT] = "request.forwarded_port",
          [HEADER_NAME_DISPATCH_ECHO] = "on",
        }
      })

      local body = assert.res_status(200, res)
      assert.matches("^[0-9]+$", body)
      assert.logfile().has.no.line("[error]", true, 0)
      assert.logfile().has.no.line("[crit]",  true, 0)
    end)

    it("read kong.request.forwarded_scheme", function()
      local client = helpers.proxy_client()
      finally(function() client:close() end)

      local res = assert(client:send {
        method = "GET",
        path = "/single/status/200",
        headers = {
          [HEADER_NAME_TEST] = "get_kong_property",
          [HEADER_NAME_INPUT] = "request.forwarded_scheme",
          [HEADER_NAME_DISPATCH_ECHO] = "on",
        }
      })

      local body = assert.res_status(200, res)
      assert.equal("http", body)
      assert.logfile().has.no.line("[error]", true, 0)
      assert.logfile().has.no.line("[crit]",  true, 0)
    end)

    pending("read kong.response.source", function()
      local client = helpers.proxy_client()
      finally(function() client:close() end)

      local res = assert(client:send {
        method = "GET",
        path = "/single/status/200",
        headers = {
          [HEADER_NAME_PHASE] = "log",
          [HEADER_NAME_TEST] = "get_kong_property",
          [HEADER_NAME_INPUT] = "response.source",
          [HEADER_NAME_DISPATCH_ECHO] = "on",
        }
      })

      local body = assert.res_status(200, res)
      assert.equal("service", body)
      assert.logfile().has.no.line("[error]", true, 0)
      assert.logfile().has.no.line("[crit]",  true, 0)
    end)

    it("read kong.router.route", function()
      local client = helpers.proxy_client()
      finally(function() client:close() end)

      local res = assert(client:send {
        method = "GET",
        path = "/single/status/200",
        headers = {
          [HEADER_NAME_TEST] = "get_kong_property",
          [HEADER_NAME_INPUT] = "router.route",
          [HEADER_NAME_DISPATCH_ECHO] = "on",
        }
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.equal(json.id, r_single.id)
      assert.logfile().has.no.line("[error]", true, 0)
      assert.logfile().has.no.line("[crit]",  true, 0)
    end)

    it("read kong.router.service", function()
      local client = helpers.proxy_client()
      finally(function() client:close() end)

      local res = assert(client:send {
        method = "GET",
        path = "/single/status/200",
        headers = {
          [HEADER_NAME_TEST] = "get_kong_property",
          [HEADER_NAME_INPUT] = "router.service",
          [HEADER_NAME_DISPATCH_ECHO] = "on",
        }
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.equal(json.id, mock_service.id)
      assert.logfile().has.no.line("[error]", true, 0)
      assert.logfile().has.no.line("[crit]",  true, 0)
    end)

    it("write kong.service.target", function()
      local client = helpers.proxy_client()
      finally(function() client:close() end)

      local target = helpers.mock_upstream_host .. ":" ..
                     helpers.mock_upstream_port

      local res = assert(client:send {
        method = "GET",
        path = "/single/status/200",
        headers = {
          [HEADER_NAME_TEST] = "set_kong_property",
          [HEADER_NAME_INPUT] = "service.target=" .. target,
          [HEADER_NAME_DISPATCH_ECHO] = "on",
        }
      })

      assert.res_status(200, res)
      -- TODO read back property
      assert.logfile().has.no.line("[error]", true, 0)
      assert.logfile().has.no.line("[crit]",  true, 0)
    end)

    -- observing weird behavior in this one:
    -- target is being set to mock_upstream:15555 instead of
    -- 127.0.0.1:1555 as expected...
    pending("write kong.service.upstream", function()
      local client = helpers.proxy_client()
      finally(function() client:close() end)

      local res = assert(client:send {
        method = "GET",
        path = "/single/status/200",
        headers = {
          [HEADER_NAME_PHASE] = "request_headers",
          [HEADER_NAME_TEST] = "set_kong_property",
          [HEADER_NAME_INPUT] = "service.upstream=mock_upstream",
          [HEADER_NAME_DISPATCH_ECHO] = "on",
        }
      })

      assert.res_status(200, res)
      -- TODO read back property
      assert.logfile().has.no.line("[error]", true, 0)
      assert.logfile().has.no.line("[crit]",  true, 0)
    end)

    it("write kong.service.request.scheme", function()
      local client = helpers.proxy_client()
      finally(function() client:close() end)

      local res = assert(client:send {
        method = "GET",
        path = "/single/status/200",
        headers = {
          [HEADER_NAME_TEST] = "set_kong_property",
          [HEADER_NAME_INPUT] = "service.request.scheme=http",
          [HEADER_NAME_DISPATCH_ECHO] = "on",
        }
      })

      assert.res_status(200, res)
      assert.logfile().has.no.line("[error]", true, 0)
      assert.logfile().has.no.line("[crit]",  true, 0)
    end)

    pending("read kong.service.response.status", function()
      local client = helpers.proxy_client()
      finally(function() client:close() end)

      local res = assert(client:send {
        method = "GET",
        path = "/single/status/200",
        headers = {
          [HEADER_NAME_PHASE] = "log",
          [HEADER_NAME_TEST] = "get_kong_property",
          [HEADER_NAME_INPUT] = "service.response.status",
          [HEADER_NAME_DISPATCH_ECHO] = "on",
        }
      })

      local body = assert.res_status(200, res)
      assert.equal("200", body)
      assert.logfile().has.no.line("[error]", true, 0)
      assert.logfile().has.no.line("[crit]",  true, 0)
    end)

    it("write kong.response.status", function()
      local client = helpers.proxy_client()
      finally(function() client:close() end)

      local res = assert(client:send {
        method = "GET",
        path = "/single/status/200",
        headers = {
          [HEADER_NAME_PHASE] = "response_headers",
          [HEADER_NAME_TEST] = "set_kong_property",
          [HEADER_NAME_INPUT] = "response.status=203",
          [HEADER_NAME_DISPATCH_ECHO] = "on",
        }
      })

      assert.res_status(203, res)
      -- TODO read back property
      assert.logfile().has.no.line("[error]", true, 0)
      assert.logfile().has.no.line("[crit]",  true, 0)
    end)

    it("read kong.configuration", function()
      local client = helpers.proxy_client()
      finally(function() client:close() end)

      local res = assert(client:send {
        method = "GET",
        path = "/single/status/200",
        headers = {
          [HEADER_NAME_TEST] = "get_kong_property",
          [HEADER_NAME_INPUT] = "configuration.role",
          [HEADER_NAME_DISPATCH_ECHO] = "on",
        }
      })

      local body = assert.res_status(200, res)
      assert.equal("traditional", body)
      assert.logfile().has.no.line("[error]", true, 0)
      assert.logfile().has.no.line("[crit]",  true, 0)
    end)

    it("read kong.route_id", function()
      local client = helpers.proxy_client()
      finally(function() client:close() end)

      local res = assert(client:send {
        method = "GET",
        path = "/single/status/201",
        headers = {
          [HEADER_NAME_TEST] = "get_kong_property",
          [HEADER_NAME_INPUT] = "route_id",
          [HEADER_NAME_DISPATCH_ECHO] = "on",
        }
      })

      local body = assert.res_status(200, res)
      assert.equal(r_single.id, body)
      assert.logfile().has.no.line("[error]", true, 0)
      assert.logfile().has.no.line("[crit]",  true, 0)
    end)

    it("read kong.service_id", function()
      local client = helpers.proxy_client()
      finally(function() client:close() end)

      local res = assert(client:send {
        method = "GET",
        path = "/single/status/201",
        headers = {
          [HEADER_NAME_TEST] = "get_kong_property",
          [HEADER_NAME_INPUT] = "service_id",
          [HEADER_NAME_DISPATCH_ECHO] = "on",
        }
      })

      local body = assert.res_status(200, res)
      assert.equal(mock_service.id, body)
      assert.logfile().has.no.line("[error]", true, 0)
      assert.logfile().has.no.line("[crit]",  true, 0)
    end)

    it("read kong.ctx.shared[<attr>]", function()
      local client = helpers.proxy_client()
      finally(function() client:close() end)

      local res = assert(client:send {
        method = "GET",
        path = "/lua/status/200",
        headers = {
          [HEADER_NAME_LUA_PROPERTY] = "foo",
          [HEADER_NAME_LUA_VALUE] = "bar",
          [HEADER_NAME_TEST] = "get_kong_property",
          [HEADER_NAME_INPUT] = "ctx.shared.foo",
          [HEADER_NAME_DISPATCH_ECHO] = "on",
        }
      })

      local body = assert.res_status(200, res)
      assert.equal("bar", body)
      assert.logfile().has.no.line("[error]", true, 0)
      assert.logfile().has.no.line("[crit]",  true, 0)
    end)

    it("write kong.ctx.shared[<attr>]", function()
      local client = helpers.proxy_client()
      finally(function() client:close() end)

      local res = assert(client:send {
        method = "GET",
        path = "/lua/status/200",
        headers = {
          [HEADER_NAME_LUA_PROPERTY] = "foo",
          [HEADER_NAME_TEST] = "set_kong_property",
          [HEADER_NAME_INPUT] = "ctx.shared.foo=bar",
          [HEADER_NAME_DISPATCH_ECHO] = "on",
        }
      })

      assert.res_status(200, res)
      local value = assert.response(res).has.header(HEADER_NAME_LUA_VALUE)
      assert.same("bar", value)
      assert.logfile().has.no.line("[error]", true, 0)
      assert.logfile().has.no.line("[crit]",  true, 0)
    end)

    it("clear kong.ctx.shared[<attr>]", function()
      local client = helpers.proxy_client()
      finally(function() client:close() end)

      local res = assert(client:send {
        method = "GET",
        path = "/lua/status/200",
        headers = {
          [HEADER_NAME_LUA_PROPERTY] = "foo",
          [HEADER_NAME_LUA_VALUE] = "bar",
          [HEADER_NAME_TEST] = "set_kong_property",
          [HEADER_NAME_INPUT] = "ctx.shared.foo",
          [HEADER_NAME_DISPATCH_ECHO] = "on",
        }
      })

      assert.res_status(200, res)
      assert.response(res).has.no.header(HEADER_NAME_LUA_VALUE)
      assert.logfile().has.no.line("[error]", true, 0)
      assert.logfile().has.no.line("[crit]",  true, 0)
    end)

    it("send an http dispatch, return its response body", function()
      local client = helpers.proxy_client()
      finally(function() client:close() end)

      local res = assert(client:send {
        method = "GET",
        path = "/single/status/201",
        headers = {
          [HEADER_NAME_TEST] = "echo_http_dispatch",
          [HEADER_NAME_INPUT] = "path=/headers",
          [HEADER_NAME_DISPATCH_ECHO] = "on",
        }
      })

      -- The dispatch went to the local mock upstream /headers endpoint
      -- which itself sent back
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.equal(helpers.mock_upstream_host .. ":" .. helpers.mock_upstream_port,
                   json.headers["host"])
      assert.equal("http://" .. helpers.mock_upstream_host .. ":" ..
                   helpers.mock_upstream_port .. "/headers",
                   json.url)

      assert.logfile().has.no.line("[error]", true, 0)
      assert.logfile().has.no.line("[crit]",  true, 0)
    end)

    it("resolves DNS hostnames to send an http dispatch, return its response body", function()
      local client = helpers.proxy_client()
      finally(function() client:close() end)

      local res = assert(client:send {
        method = "GET",
        path = "/single/status/201",
        headers = {
          [HEADER_NAME_TEST] = "echo_http_dispatch",
          [HEADER_NAME_INPUT] = "path=/headers host=" .. MOCK_UPSTREAM_DNS_ADDR,
          [HEADER_NAME_DISPATCH_ECHO] = "on",
        }
      })

      -- The dispatch went to the local mock upstream /headers endpoint
      -- which itself sent back
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.equal(MOCK_UPSTREAM_DNS_ADDR, json.headers["host"])
      assert.equal("http://" .. MOCK_UPSTREAM_DNS_ADDR .. "/headers",
                   json.url)

      assert.logfile().has.no.line("[error]", true, 0)
      assert.logfile().has.no.line("[crit]",  true, 0)

      assert.logfile().has.line("wasm lua resolver using existing dns_client")
      assert.logfile().has.line([[wasm lua resolved "]]
                                .. DNS_HOSTNAME ..
                                [[" to "127.0.0.1"]])
    end)

    pending("start on_tick background timer", function()
      -- Pending on internal ngx_wasm_module changes
      local client = helpers.proxy_client()
      finally(function() client:close() end)

      local res = assert(client:send {
        method = "GET",
        path = "/single/status/200",
      })

      assert.res_status(200, res)
      assert.logfile().has.no.line("[error]", true, 0)
      assert.logfile().has.no.line("[crit]",  true, 0)

      -- TODO
    end)
  end)

  describe("behavior with", function()
    pending("multiple filters, one sends a local response", function()
      local client = helpers.proxy_client()
      finally(function() client:close() end)

      local res = assert(client:send {
        method = "GET",
        path = "/double/",
        headers = {
          [HEADER_NAME_TEST] = "local_response",
        }
      })

      local body = assert.res_status(200, res)
      assert.equal("", body)
      assert.logfile().has.no.line("[error]", true, 0)
      assert.logfile().has.no.line("[crit]",  true, 0)

      -- TODO: test that phases are properly invoked and the chain
      --       correctly interrupted, but how?
      --       no equivalent to Test::Nginx's grep_error_log_out
    end)
  end)
end)

end -- each strategy
