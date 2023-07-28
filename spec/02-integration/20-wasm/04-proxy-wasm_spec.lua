local helpers = require "spec.helpers"
local cjson = require "cjson"


local DATABASE = "postgres"
local HEADER_NAME_PHASE = "X-PW-Phase"
local HEADER_NAME_TEST = "X-PW-Test"
local HEADER_NAME_INPUT = "X-PW-Input"
local HEADER_NAME_DISPATCH_ECHO = "X-PW-Dispatch-Echo"
local HEADER_NAME_ADD_REQ_HEADER = "X-PW-Add-Header"
local HEADER_NAME_ADD_RESP_HEADER = "X-PW-Add-Resp-Header"

local DNS_HOSTNAME = "wasm.test"
local MOCK_UPSTREAM_DNS_ADDR = DNS_HOSTNAME .. ":" .. helpers.mock_upstream_port


describe("proxy-wasm filters (#wasm)", function()
  local r_single, mock_service
  local hosts_file

  lazy_setup(function()
    require("kong.runloop.wasm").enable({
      { name = "tests" },
    })

    local bp, db = helpers.get_db_utils(DATABASE, {
      "routes",
      "services",
      "filter_chains",
    })

    mock_service = assert(bp.services:insert {
      host = helpers.mock_upstream_host,
      port = helpers.mock_upstream_port,
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

    assert(db.filter_chains:insert {
      route = r_single,
      filters = {
        { name = "tests" },
      },
    })

    assert(db.filter_chains:insert {
      route = r_double,
      filters = {
        { name = "tests" },
        { name = "tests" },
      },
    })

    -- XXX our dns mock fixture doesn't work when called from wasm land
    hosts_file = os.tmpname()
    assert(helpers.file.write(hosts_file,
                              "127.0.0.1 " .. DNS_HOSTNAME .. "\n"))

    assert(helpers.start_kong({
      database = DATABASE,
      nginx_conf = "spec/fixtures/custom_nginx.template",
      wasm = true,
      dns_hostsfile = hosts_file,
    }))
  end)

  lazy_teardown(function()
    helpers.stop_kong(nil, true)
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
      assert.equal("proxy-wasm", json.headers["via"])
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
