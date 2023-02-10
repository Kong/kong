local helpers = require "spec.helpers"
local cjson = require "cjson"


local DATABASE = "postgres"
local PROXY_WASM_PATH = "./spec/fixtures/proxy_wasm_filters"

local HEADER_NAME_PHASE = "X-PW-Phase"
local HEADER_NAME_TEST = "X-PW-Test"
local HEADER_NAME_INPUT = "X-PW-Input"
local HEADER_NAME_DISPATCH_ECHO = "X-PW-Dispatch-Echo"
local HEADER_NAME_ADD_REQ_HEADER = "X-PW-Add-Header"
local HEADER_NAME_ADD_RESP_HEADER = "X-PW-Add-Resp-Header"

local ERROR_OR_CRIT = "\\[(error|crit)\\]"


describe("Plugin: proxy-wasm filters (#wasm)", function()
  lazy_setup(function()
    assert(helpers.execute("cd " .. PROXY_WASM_PATH .. " && " ..
                           "cargo build --lib --target wasm32-wasi"))

    local bp = helpers.get_db_utils(DATABASE, {
      "routes",
      "services",
    }, { "proxy-wasm" })

    local mock_service = assert(bp.services:insert {
      host = helpers.mock_upstream_host,
      port = helpers.mock_upstream_port,
    })

    local r_single = assert(bp.routes:insert {
      paths = { "/single" },
      strip_path = true,
      service = mock_service,
    })

    local r_double = assert(bp.routes:insert {
      paths = { "/double" },
      strip_path = true,
      service = mock_service,
    })

    assert(bp.plugins:insert {
      name = "proxy-wasm",
      route = r_single,
      config = {
        filters = {
          --{ name = "tests", config = "tick_every=1000" },
          { name = "tests" },
        },
      },
    })

    assert(bp.plugins:insert {
      name = "proxy-wasm",
      route = r_double,
      config = {
        filters = {
          { name = "tests" },
          { name = "tests" },
        },
      },
    })

    assert(helpers.start_kong {
      database = DATABASE,
      plugins = "bundled, proxy-wasm",
      nginx_conf = "spec/fixtures/custom_nginx.template",
      wasm_modules = PROXY_WASM_PATH .. "/target/wasm32-wasi/debug/tests.wasm",
    })
  end)

  lazy_teardown(function()
    helpers.stop_kong(nil, true)
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
      assert.logfile().has.no.line(ERROR_OR_CRIT)
    end)

    it("with multiple filters", function()
      local client = helpers.proxy_client()
      finally(function() client:close() end)

      local res = assert(client:send {
        method = "GET",
        path = "/double/status/200",
      })

      assert.res_status(200, res)
      assert.logfile().has.no.line(ERROR_OR_CRIT)
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
      assert.equal("proxy-wasm", json.headers["via"])
      -- TODO: honor case-sensitivity (proxy-wasm-rust-sdk/ngx_wasm_module investigation)
      -- assert.equal("proxy-wasm", json.headers["Via"])
      assert.logfile().has.no.line(ERROR_OR_CRIT)
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
      assert.logfile().has.no.line(ERROR_OR_CRIT)
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
      assert.logfile().has.no.line(ERROR_OR_CRIT)
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
      assert.logfile().has.no.line(ERROR_OR_CRIT)
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
      assert.logfile().has.line("cannot add response header: headers already sent")
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

    it("send a local response", function()
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
      assert.logfile().has.no.line(ERROR_OR_CRIT)
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

      assert.logfile().has.no.line(ERROR_OR_CRIT)
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
      assert.logfile().has.no.line(ERROR_OR_CRIT)
      -- TODO
    end)
  end)

  describe("behavior with", function()
    it("multiple filters, one sends a local response", function()
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
      assert.logfile().has.no.line(ERROR_OR_CRIT)
      -- TODO: test that phases are properly invoked and the chain
      --       correctly interrupted, but how?
      --       no equivalent to Test::Nginx's grep_error_log_out
    end)
  end)
end)
