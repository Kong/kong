-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local helpers    = require "spec.helpers"
local ws         = require "spec-ee.fixtures.websocket"
local ee_helpers = require "spec-ee.helpers"
local utils      = require "kong.tools.utils"

local fmt = string.format

local MODES = {
  "route",
  "service",
  "global",
}

local SCHEMES = {
  "ws",
  "wss",
}

local function each(tbl)
  local i = 0
  return function()
    i = i + 1
    return tbl[i]
  end
end

local DIR = "/tmp/websocket." .. ngx.worker.pid()

for mode in each(MODES) do
for scheme in each(SCHEMES) do
for _, strategy in helpers.each_strategy() do

describe(fmt("#%s WebSocket (%s) %s plugin handlers", strategy, scheme, mode), function()

  local ID = utils.uuid()
  local expect_certificate = scheme == "wss" and mode == "global"

  local function writer(handler)
    local fname = fmt("%s/%s.%s.%s", DIR, handler, mode, ID)
    return { fmt([[
      local fname = %q
      local fh = assert(io.open(fname, "w+"))
      fh:write("OK")
      fh:close()
    ]], fname) }
  end

  local function assert_handler_executed(handler)
    local fname = fmt("%s/%s.%s.%s", DIR, handler, mode, ID)
    assert
      .with_timeout(10)
      .eventually(function()
        local content = assert(helpers.file.read(fname))
        assert.same("OK", content)
      end)
      .has_no_error("waiting for " .. fname .. " contents to equal 'OK'")
  end

  local function assert_not_handler_executed(handler)
    -- first confirm that the last WS handler that we expect to execute has
    -- indeed run
    assert_handler_executed("ws_close")

    local should_not_exist = fmt("%s/%s.%s.%s", DIR, handler, mode, ID)
    assert.falsy(helpers.path.exists(should_not_exist),
                 fmt("expected handler %s not to be executed", handler))
  end


  lazy_setup(function()
    assert(helpers.path.mkdir(DIR))

    local bp = helpers.get_db_utils(
      strategy,
      {
        "routes",
        "services",
        "plugins",
      },
      { "pre-function", "post-function" }
    )


    local service = assert(bp.services:insert({
      name  = "ws.test",
      protocol = "ws",
    }))

    local route = assert(bp.routes:insert({
      name  = "ws.test",
      hosts = { "ws.test" },
      protocols = { scheme },
      service = service,
    }))

    local plugin_service, plugin_route
    if mode == "service" then
      plugin_service = service
      plugin_route = nil

    elseif mode == "route" then
      plugin_service = nil
      plugin_route = route

    elseif mode == "global" then
      plugin_service = nil
      plugin_route = nil
    end

    assert(bp.plugins:insert {
      name = "pre-function",
      service = plugin_service,
      route = plugin_route,
      protocols = { "ws", "wss" },
      config = {
        ws_close = writer("ws_close"),
        ws_handshake = writer("ws_handshake"),
        ws_client_frame = writer("ws_client_frame"),
        ws_upstream_frame = writer("ws_upstream_frame"),

        certificate = writer("certificate"),
        rewrite = writer("rewrite"),

        access = writer("access"),
        body_filter = writer("body_filter"),
        header_filter = writer("header_filter"),
        log = writer("log"),
      },
    })

    assert(helpers.start_kong({
      database = strategy,
      nginx_conf = "spec/fixtures/custom_nginx.template",
      log_level = "debug",
      untrusted_lua = "on",
    }, nil, nil, { http_mock = { ws = ws.mock_upstream() } }))
  end)

  lazy_teardown(function()
    helpers.stop_kong()

    if helpers.path.isdir(DIR) then
      assert(helpers.dir.rmtree(DIR))
    end
  end)

  before_each(function()
    local conn = assert(ee_helpers.ws_proxy_client({
      scheme = scheme,
      path = "/",
      host = "ws.test",
      query = { id = ID },
    }))

    assert(conn:send_text("yelllo"))
    assert(conn:recv_frame())
    assert(conn:send_close())
    conn:close()
  end)

  describe("WebSocket handlers", function()
    it("ws_handshake", function()
      assert_handler_executed("ws_handshake")
    end)

    it("ws_client_frame", function()
      assert_handler_executed("ws_client_frame")
    end)

    it("ws_upstream_frame", function()
      assert_handler_executed("ws_upstream_frame")
    end)

    it("ws_close", function()
      assert_handler_executed("ws_close")
    end)
  end)

  describe("non-WebSocket handlers (executed)", function()
    if expect_certificate then
      it("certificate", function()
        assert_handler_executed("certificate")
      end)
    end

    it("rewrite", function()
      assert_handler_executed("ws_handshake")
    end)
  end)

  describe("non-WebSocket handlers (skipped)", function()
    if not expect_certificate then
      it("certificate", function()
        assert_not_handler_executed("certificate")
      end)
    end

    it("access", function()
      assert_not_handler_executed("access")
    end)

    it("body_filter", function()
      assert_not_handler_executed("body_filter")
    end)

    it("header_filter", function()
      assert_not_handler_executed("header_filter")
    end)

    it("log", function()
        assert_not_handler_executed("log")
    end)
  end)
end)

end -- each strategy
end -- each scheme
end -- each mode
