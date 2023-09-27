-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson"
local ee_helpers = require "spec-ee.helpers"
local ssl_fixtures = require "spec.fixtures.ssl"
local ws = require "spec-ee.fixtures.websocket"
local utils = require "kong.tools.utils"
local inspect = require "inspect"

local ws_proxy_client = ee_helpers.ws_proxy_client
local fmt = string.format
local insert = table.insert

local function now()
  ngx.update_time()
  return ngx.now()
end

local ERRORS = {
  BAD_HANDSHAKE = {
    port = 20001,
    port_alt = 20005,
    retries = 3,
  },
  TIMEOUT = {
    port = 20002,
    timeout = 1000,
    retries = 1,
  },
}


local PORTS = {
  bad_handshake     = ERRORS.BAD_HANDSHAKE.port,
  timeout           = ERRORS.TIMEOUT.port,
  mtls              = 20004,
  bad_handshake_alt = ERRORS.BAD_HANDSHAKE.port_alt,
  plain             = ws.const.ports.ws,
  tls               = ws.const.ports.wss,
  ["service-mtls"]  = ws.const.ports.wss,
  ["upstream-mtls"] = ws.const.ports.wss,
}

local fixtures = {
  dns_mock = helpers.dns_mock.new(),

  http_mock = {
    ws = ws.mock_upstream(),
  },

  stream_mock = {
    bad_handshake = fmt([[
      server {
        listen %s;

        content_by_lua_block {
          ngx.exit(444)
        }
      }

      server {
        listen %s;

        content_by_lua_block {
          ngx.exit(444)
        }
      }
    ]], PORTS.bad_handshake, PORTS.bad_handshake_alt),

    timeout = fmt([[
      server {
        listen %s;
        content_by_lua_block {
          local ms = %s
          local delay = (ms * 1000) * 2
          ngx.sleep(delay)
        }
      }
    ]], PORTS.timeout, ERRORS.TIMEOUT.timeout),
  },
}

local function each(...)
  local items = { ... }
  local iter = ipairs(items)
  local i, item = 0, nil
  return function()
    i, item = iter(items, i)
    return item
  end
end

-- protocol aliases
--
-- saves a whole bunch of ternary/if-else code
local PROTO = {
  ws = {
    [true]    = "wss",
    [false]   = "ws",
    ["http"]  = "ws",
    ["https"] = "wss",
    ["ws"]    = "ws",
    ["wss"]   = "wss",
  },

  http = {
    [true]    = "https",
    [false]   = "http",
    ["ws"]    = "http",
    ["wss"]   = "https",
    ["http"]  = "http",
    ["https"] = "https",
  },

  boolean = {
    [true]    = true,
    [false]   = false,
    ["http"]  = false,
    ["https"] = true,
    ["ws"]    = false,
    ["wss"]   = true,
  },
}
PROTO.proxy_pass = PROTO.http
PROTO.websocket = PROTO.ws

local UPSTREAM_MODE = {
  [false] = {
    [true] = "none",
    [false] = "none",
  },
  [true] = {
    [true] = "mTLS",
    [false] = "TLS",
  },
}


---@alias ws.http.proto '"http"'|'"https"'

---@alias ws.ws.proto '"ws"'|'"wss"'

---@alias ws.proto ws.http.proto|ws.ws.proto

---@class ws.test_case : table
---@field slug          string
---@field id            string
---@field use_upstream  boolean
---@field service_ssl   boolean
---@field service_mtls  boolean
---@field service_client_cert? kong.db.entities.Certificate
---@field upstream_mtls boolean
---@field upstream_client_cert? kong.db.entities.Certificate
---@field service_host  string
---@field route_ssl     boolean
---@field service_proto ws.proto
---@field route_proto   ws.proto
---@field mode          '"websocket"'|'"proxy_pass"'
---@field route_host    string
---@field route_path    string
---@field client_scheme ws.ws.proto
---@field client_http_scheme '"http"'|'"https"'
---@field upstream_port number
---
---@field route kong.db.entities.Route
---@field service kong.db.entities.Service
---@field upstream kong.db.entities.Upstream|nil
---@field targets kong.db.entities.Target[]|nil


---@type ws.test_case[]
local CASES = {}

-- test case permutations
--
-- there are a lot of combinations we want to test out:
do
  -- mode:
  --   * proxy_pass: proxying transparently using http/https services
  --   * websocket: proxying using the new WebSocket services/routes
  for mode in each("proxy_pass", "websocket") do

    -- route_ssl dictates if the connection between the client and Kong uses TLS
    for route_ssl in each(true, false) do
      local route_proto = PROTO[mode][route_ssl]
      local client_scheme = PROTO.websocket[route_ssl]

      -- service_ssl_mode dictates if the connection between Kong and the upstream
      -- uses TLS and if mTLS is used
      for service_ssl_mode in each("plain", "tls", "service-mtls", "upstream-mtls") do
        local service_ssl = service_ssl_mode ~= "plain"
        local service_mtls = service_ssl_mode == "service-mtls"
        local upstream_mtls = service_ssl_mode == "upstream-mtls"

        local service_proto = PROTO[mode][service_ssl]

        local upstream_port = PORTS[service_ssl_mode]

        -- use_upstream controls whether the service points directly to an
        -- addr:host or if we should use an upstream+targets
        --
        -- When use_upstream is true, we'll provision an upstream with two
        -- targets: a proper one, and one that returns an error. This way we
        -- excercise the balancer code
        for use_upstream in each(true, false) do
          local skip = false
          if upstream_mtls and not use_upstream then
            skip = true
          end


          if not skip then
            local route_host = fmt(
              "%s-to-%s-%s-%s.test",
              route_proto,
              service_proto,
              service_ssl_mode,
              use_upstream and "with-upstream" or "no-upstream"
            )

            local service_host = route_host:gsub("%.test$", ".service")

            local slug = fmt(
              "(route: %s) - (service: %s%s) - (upstream: %s)",
              route_proto,
              service_proto,
              service_mtls and "+mTLS" or "",
              UPSTREAM_MODE[use_upstream][upstream_mtls]
            )

            insert(CASES, {
              slug          = slug,
              id            = utils.uuid(),
              mode          = mode,
              use_upstream  = use_upstream,
              service_ssl   = service_ssl,
              service_mtls  = service_mtls,
              service_proto = service_proto,
              service_host  = service_host,
              upstream_port = upstream_port,
              upstream_mtls = upstream_mtls,
              route_ssl     = route_ssl,
              route_proto   = route_proto,
              route_host    = route_host,
              client_scheme = client_scheme,
            })

          end
        end

      end

    end
  end
end

---
-- Establish a WS connection.
--
---@param case ws.test_case
local function connect(case, opts)
  opts = opts or {}
  opts.scheme = opts.scheme or case.client_scheme
  opts.path = opts.path or case.route_path
  opts.host = opts.host or case.route_host

  -- inject a request ID header
  opts.headers = opts.headers or {}
  opts.headers[ws.const.headers.id] = utils.uuid()

  return ws_proxy_client(opts)
end

---
-- Perform a WS handshake request and retrieve the response.
--
-- This is for testing handshake response semantics and closes
-- the WS connection immediately after connecting.
--
---@param case  ws.test_case
---@param path? string
local function handshake(case, path)
  path = path or "/"
  local wc, err = connect(case, {
    path = path,
    fail_on_error = false
  })

  assert.is_nil(err)
  assert.not_nil(wc)

  wc.response:read_body()
  wc:close()

  return wc.response, wc.id
end

for _, strategy in helpers.each_strategy() do
describe("WebSockets [db #" .. strategy .. "]", function()
  setup(function()
    local bp = helpers.get_db_utils(strategy, {
      "routes",
      "services",
      "upstreams",
      "targets",
      "plugins",
    })

    assert(bp.plugins:insert({
      name = "post-function",
      config = {
        log = {
          [[require("spec-ee.fixtures.websocket.upstream").log_to_shm()]]
        },
        ws_close = {
          [[require("spec-ee.fixtures.websocket.upstream").log_to_shm()]]
        },
      },
    }))

    local client_cert = assert(bp.certificates:insert({
      cert = ssl_fixtures.cert_client,
      key = ssl_fixtures.key_client,
    }))

    for _, case in ipairs(CASES) do
      fixtures.dns_mock:A {
        name = case.route_host,
        address = "127.0.0.1",
      }
      fixtures.dns_mock:A {
        name = case.service_host,
        address = "127.0.0.1",
      }

      if case.upstream_mtls then
        case.upstream_client_cert = client_cert
      end

      if case.service_mtls then
        case.service_client_cert = client_cert
      end


      -- regular, happy service
      do
        local upstream

        if case.use_upstream then
          local addr = case.service_host

          upstream = assert(bp.upstreams:insert {
            name               = case.service_host,
            host_header        = case.service_host,
            client_certificate = case.upstream_client_cert,
          })

          case.targets = {
            assert(bp.targets:insert {
              target   = addr .. ":" .. case.upstream_port,
              upstream = upstream,
              weight   = 50,
            }),

            assert(bp.targets:insert {
              target   = addr .. ":" .. PORTS.bad_handshake,
              upstream = upstream,
              weight   = 100,
            })
          }
        end

        local service = bp.services:insert {
          name               = case.route_host,
          protocol           = case.service_proto,
          host               = case.service_host,
          port               = case.upstream_port,
          client_certificate = case.service_client_cert,
        }

        local route = bp.routes:insert {
          name        = case.route_host,
          protocols   = { case.route_proto },
          hosts       = { case.route_host },
          service     = service,
        }

        case.upstream = upstream
        case.service  = service
        case.route    = route
      end

      -- service where each target returns an invalid http response
      do
        local upstream

        local name = case.route_host .. "-all-targets-fail"

        local addr = helpers.mock_upstream_host

        upstream = assert(bp.upstreams:insert {
          name = name,
        })

        assert(bp.targets:insert {
          target = addr .. ":" .. PORTS.bad_handshake,
          upstream = upstream,
          weight = 50,
        })

        assert(bp.targets:insert {
          target = addr .. ":" .. PORTS.bad_handshake_alt,
          upstream = upstream,
          weight = 100,
        })

        local service = bp.services:insert {
          name               = name,
          protocol           = case.service_proto,
          host               = upstream and upstream.name,
          port               = case.upstream_port,
          client_certificate = case.service_client_cert,
          retries            = ERRORS.BAD_HANDSHAKE.retries,
        }

        bp.routes:insert {
          name        = name,
          protocols   = { case.route_proto },
          paths       = { "/upstream-all-targets-fail" },
          hosts       = { case.route_host },
          service     = service,
        }
      end

      -- service that times out connecting to its upstream
      do
        local name = case.route_host .. "-timeout"
        local upstream

        if case.use_upstream then
          local addr = case.service_host

          upstream = assert(bp.upstreams:insert {
            name               = name,
            host_header        = case.service_host,
            client_certificate = case.upstream_client_cert,
          })

          case.targets = {
            assert(bp.targets:insert {
              target   = addr .. ":" .. PORTS.timeout,
              upstream = upstream,
              weight   = 100,
            })
          }
        end

        local service = bp.services:insert {
          name               = name,
          protocol           = case.service_proto,
          port               = PORTS.timeout,
          client_certificate = case.service_client_cert,
          host               = upstream and upstream.name or case.service_host,
          connect_timeout    = ERRORS.TIMEOUT.timeout,
          read_timeout       = ERRORS.TIMEOUT.timeout,
          write_timeout      = ERRORS.TIMEOUT.timeout,
          retries            = ERRORS.TIMEOUT.retries,
        }

        bp.routes:insert {
          name        = name,
          protocols   = { case.route_proto },
          paths       = { "/upstream-timeout" },
          hosts       = { case.route_host },
          service     = service,
        }
      end
    end

    assert(helpers.start_kong({
      database      = strategy,
      plugins       = "bundled",
      nginx_events_worker_connections = 2048,
      nginx_conf    = "spec/fixtures/custom_nginx.template",
      headers       = "server_tokens,latency_tokens",
      untrusted_lua = "on",
      vitals        = "off",

      -- we don't actually use any stream proxy features in this test suite,
      -- but this is needed in order to load our forward-proxy stream_mock fixture
      stream_listen = helpers.get_proxy_ip(false) .. ":19000",
    }, nil, false, fixtures ))
  end)

  teardown(function()
    helpers.stop_kong(nil, true)
  end)

  for _, case in ipairs(CASES) do
    describe(case.slug .. " #handshake", function()
      local res

      lazy_setup(function()
        res = handshake(case)
      end)

      it("returns a 101 response code", function()
        assert.not_nil(res, "no response from ws handshake")
        assert.response(res).has.status(101)

        assert.equals(1.1, res.version)
        assert.equals("Switching Protocols", res.reason)
      end)

      it("returns a Sec-WebSocket-Accept header", function()
        assert.response(res).has.header("sec-websocket-accept")
      end)

      it("returns the correct Connection header", function()
        local conn = assert.response(res).has.header("connection")
        assert.equals("upgrade", conn:lower())
      end)

      it("returns the correct Upgrade header", function()
        local upgrade = assert.response(res).has.header("upgrade")
        assert.equals("websocket", upgrade:lower())
      end)

      it("returns the correct Via header", function()
        local via = assert.response(res).has.header("via")
        assert.matches("kong", via)
      end)

      it("returns other headers sent by the upstream", function()
        local value = assert.response(res).has.header(ws.const.headers.self)
        assert.equals("1", value)
      end)

      it("correctly handles repeated/multi-value headers", function()
        local value = assert.response(res).has.header(ws.const.headers.multi)
        assert.same({ "one", "two" }, value)
      end)

      it("forwards upstream headers on failure", function()
        res = handshake(case, "/status/403")
        assert.res_status(403, res)
        assert.response(res).has_header(ws.const.headers.id)
        assert.response(res).has_header(ws.const.headers.self)
      end)
    end)

    describe(case.slug .. " request", function()
      local request

      lazy_setup(function()
        local wc = connect(case, {
          path = "/test",
          query = { a = "1", b = true },
          headers = {
            foo = "bar",
            mixedCase = "mixedCase",
            UPPERCASE = "UPPERCASE",
            MixedMulti = { "abc", "DEF" },
          },
        })

        request = wc:get_request()
        wc:close()
      end)

      it("sends the correct request method", function()
        assert.equals("GET", request.method)
      end)

      it("sends the correct path", function()
        assert.equals("/test", request.uri)
      end)

      it("sends the correct query", function()
        assert.same({ a = "1", b = true }, request.query)
      end)

      it("sends all of the expected request headers to the upstream", function()
        local headers = request.headers
        local expected = {
          "connection",
          "foo",
          "host",
          "sec-websocket-key",
          "upgrade",
          "x-forwarded-for",
          "x-forwarded-path",
          "x-forwarded-port",
          "x-forwarded-prefix",
          "x-forwarded-proto",
          "x-forwarded-uri",
        }
        for _, name in ipairs(expected) do
          assert.not_nil(name, headers[name], "request header missing: " .. name)
        end

        local xfp = PROTO.http[case.route_ssl]
        assert.equals(xfp, headers["x-forwarded-proto"])

        assert.equals(case.route_host, headers["x-forwarded-host"])
      end)

      it("does not normalize/lowercase unmanaged request headers", function()
        local mixed, upper, multi

        for name, value in pairs(request.headers_raw) do
          if name == "mixedCase" then
            mixed = value

          elseif name == "UPPERCASE" then
            upper = value

          elseif name == "MixedMulti" then
            multi = value
          end
        end

        assert.not_nil(mixed, "`mixedCase` request header was missing")
        assert.equals("mixedCase", mixed)

        assert.not_nil(upper, "`UPPERCASE` request header was missing")
        assert.equals("UPPERCASE", upper)

        assert.not_nil(multi, "`MixedMulti` request header was missing")
        assert.same({ "abc", "DEF" }, multi)
      end)

      it("sends the correct host header", function()
        local exp = case.service_host .. ":" .. case.upstream_port
        assert.equals(exp, request.headers.host)
      end)

      it("sends the correct SNI to TLS services", function()
        if case.service_ssl then
          assert.equals(case.service_host, request.ssl_server_name)
        else
          assert.is_nil(request.ssl_server_name)
        end
      end)

      it("sends the proper client cert for the service/upstream", function()
        if case.service_mtls or case.upstream_mtls then
          assert.not_nil(request.ssl_client_s_dn)
          assert.equals("CN=foo@example.com,O=Kong Testing,ST=California,C=US",
                        request.ssl_client_s_dn)
        else
          assert.is_nil(request.ssl_client_s_dn)
        end
      end)
    end)

    describe(case.slug .. " messaging", function()
      local wc

      before_each(function()
        wc = connect(case)
      end)

      after_each(function()
        if wc then
          wc:close()
        end
      end)

      it("text", function()
        local payload = { message = "hello websocket" }

        assert(wc:send_text(cjson.encode(payload)))
        local frame, typ, err = wc:recv_frame()
        assert.not_nil(frame, err)
        assert.is_nil(wc.client.fatal)
        assert.equal("text", typ)
        assert.same(payload, cjson.decode(frame))

        assert(wc:send_close())
      end)

      it("binary", function()
        local payload = "abcdefg"

        assert(wc:send_binary(payload))
        local frame, typ, err = wc:recv_frame()
        assert.is_nil(wc.client.fatal)
        assert.not_nil(frame, err)
        assert.equal("binary", typ)
        assert.same(payload, frame)

        assert(wc:send_close())
      end)

      it("ping pong", function()
        local payload = { message = "give me a pong" }

        assert(wc:send_ping(cjson.encode(payload)))
        local frame, typ, err = wc:recv_frame()
        assert.is_nil(wc.client.fatal)
        assert(frame, err)
        assert.equal("pong", typ)
        assert.same(payload, cjson.decode(frame))

        assert(wc:send_close())
      end)
    end)

    describe(case.slug .. " #log data from kong.log.serialize()", function()
      local log

      local function check_table_types(exp, tbl, ...)
        local cmp = {}
        for k, v in pairs(tbl) do
          cmp[k] = type(v)
        end

        assert.same(exp, cmp, ...)
      end

      lazy_setup(function()
        local wc = connect(case)

        -- sanity
        wc:send_ping("hi")
        local frame, typ, err = wc:recv_frame()
        assert.is_nil(err)
        assert.equals("pong", typ)
        assert.equals("hi", frame)

        wc:send_close()
        wc:close()

        log = ws.get_session_log(wc)
      end)

      it("route and service", function()
        assert.equals("table", type(log.route), "request route was not logged")
        assert.equals(case.route.id, log.route.id, "log route id is incorrect")

        assert.equals("table", type(log.service), "request service was not logged")
        assert.equals(case.service.id, log.service.id, "log service log id is incorrect")
      end)

      it("request and response", function()
        assert.equals("table", type(log.request), "request was not logged")
        check_table_types({
          size        = "number",
          headers     = "table",
          method      = "string",
          uri         = "string",
          url         = "string",
          querystring = "table",
          tls         = case.route_ssl and "table" or nil,
        }, log.request, "logged request is invalid")

        check_table_types({
          headers = "table",
          size    = "number",
          status  = "number",
        }, log.response, "logged response is invalid")
      end)

      it("other important fields", function()
        assert.equals("127.0.0.1", log.client_ip, "incorrect client_ip")
        assert.equals("number", type(log.started_at), "started_at was not logged")
        assert.not_nil(log.workspace, "workspace was not logged")
      end)

      it("balancer tries", function()
        local tries = log.tries
        assert.not_nil(tries, "balancer tries was not logged")
        assert.equals("table", type(tries), "logged balancer tries is not a table")
        assert.truthy(#tries > 0, "logged balancer tries is empty")

        for i = 1, #tries - 1 do
          check_table_types({
            ip = "string",
            port = "number",
            balancer_latency = "number",
            balancer_start = "number",
            balancer_latency_ns = "number",
            balancer_start_ns = "number",
            code = "number",
            state = "string",
          }, tries[i], fmt("logged balancer try #%s is invalid", i))
        end

        check_table_types({
          ip = "string",
          port = "number",
          balancer_latency = "number",
          balancer_start = "number",
          balancer_latency_ns = "number",
          balancer_start_ns = "number",
        }, tries[#tries], "final logged balancer try is invalid")
      end)
    end)

    describe(case.slug .. " #upstream #errors", function()
      local res, id

      local function assert_balancer_tries(n)
        local log = ws.get_session_log(id)
        assert.equals(n, #log.tries, "invalid balancer tries count: "
                      .. inspect(log))
        return log
      end

      it("502 - invalid http response from targets", function()
        res, id = handshake(case, "/upstream-all-targets-fail")
        assert.res_status(502, res)

        assert_balancer_tries(ERRORS.BAD_HANDSHAKE.retries + 1)
      end)

      it("500 - upstream returns 500", function()
        res = handshake(case, "/status/500")
        assert.res_status(500, res)
      end)

      it("403 - upstream returns 403", function()
        res = handshake(case, "/status/403")
        assert.res_status(403, res)
      end)

      it("504 - upstream timeout #slow", function()
        local start = now()
        res, id = handshake(case, "/upstream-timeout")
        assert.res_status(504, res)
        local duration = now() - start

        local tries = ERRORS.TIMEOUT.retries + 1
        assert_balancer_tries(tries)

        local expected = tries * (ERRORS.TIMEOUT.timeout / 1000)

        -- the observed duration should pretty much never be _lower_ than what
        -- is expected (this would mean that something timed out earlier than it
        -- should have), but we'll allow values within 5% in order to account for
        -- clock jitter/gremlins/etc
        local min = expected * 0.95

        -- the maximum observed duration is subject to outside sources of
        -- latency (DB cache misses, test machine CPU saturation, etc), so
        -- we'll accept anything up to 50% higher than the expected value
        local max = expected * 1.5

        assert(
          duration >= min and duration < max,
          fmt("expected request to time out in >= %s < %s seconds, but it took %s seconds",
              min, max, duration)
        )
      end)
    end)

    describe(case.slug .. " #client #errors", function()
      if case.route_ssl then
        it("plaintext requests to TLS-only routes are rejected", function()
          local wc, err = connect(case, {
            scheme = "ws",
            path = "/",
            fail_on_error = false,
          })

          assert.is_nil(err)
          assert.not_nil(wc)

          wc.response:read_body()
          wc:close()

          assert.res_status(426, wc.response)

          local json = assert.response(wc.response).has.jsonbody()
          assert.same({ message = "Please use HTTPS protocol" }, json)
        end)
      end
    end)
  end
end)
end
