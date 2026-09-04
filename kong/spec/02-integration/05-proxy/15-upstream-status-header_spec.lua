local helpers = require "spec.helpers"
local constants = require "kong.constants"


local function setup_db()
  local bp = helpers.get_db_utils(nil, {
    "routes",
    "services",
    "plugins",
    "keyauth_credentials",
  }, {
    "response-phase",
  })

  local service = bp.services:insert {
    host = helpers.mock_upstream_host,
    port = helpers.mock_upstream_port,
    protocol = helpers.mock_upstream_protocol,
  }

  local route1 = bp.routes:insert {
    protocols = { "http" },
    paths = { "/status/200" },
    service = service,
  }

  local route2 = bp.routes:insert {
    protocols = { "http" },
    paths = { "/status/plugin-changes-200-to-500" },
    service = service,
  }

  bp.plugins:insert {
    name = "dummy",
    route = { id = route2.id },
    config = {
      resp_code = 500,
    }
  }

  local route3 = bp.routes:insert {
    protocols = { "http" },
    paths = { "/status/non-proxied-request" },
    service = service,
  }

  bp.plugins:insert {
    name = "key-auth",
    route = { id = route3.id },
  }

  bp.plugins:insert {
    name = "proxy-cache",
    route = { id = route1.id },
    config = {
      response_code = { 200 },
      request_method = { "GET" },
      content_type = { "application/json" },
      cache_ttl = 300,
      storage_ttl = 300,
      strategy = "memory",
    }
  }

  return bp
end


describe(constants.HEADERS.UPSTREAM_STATUS .. " header", function()
  local client

  describe("should be same as upstream status code", function()
    lazy_setup(function()
      setup_db()

      assert(helpers.start_kong {
        nginx_conf = "spec/fixtures/custom_nginx.template",
        headers = "server_tokens,latency_tokens,x-kong-upstream-status",
        plugins = "bundled,dummy",
      })
    end)

    lazy_teardown(function()
      if client then
        client:close()
      end

      helpers.stop_kong()
    end)

    before_each(function()
      if client then client:close() end
      client = helpers.proxy_client()
    end)

    it("when no plugin changes status code", function()
      local res = assert(client:send {
        method  = "GET",
        path    = "/status/200",
        headers = {
          host = helpers.mock_upstream_host,
        }
      })
      assert.res_status(200, res)
      assert.equal("200", res.headers[constants.HEADERS.UPSTREAM_STATUS])
    end)

    it("when a plugin changes status code", function()
      local res = assert(client:send {
        method  = "GET",
        host    = helpers.mock_upstream_host,
        path    = "/status/plugin-changes-200-to-500",
        headers = {
          ["Host"] = helpers.mock_upstream_host,
        }
      })
      assert.res_status(500, res)
      assert.equal("200", res.headers[constants.HEADERS.UPSTREAM_STATUS])
    end)

    it("should be set when proxy-cache is enabled", function()
      local res = assert(client:send {
        method  = "GET",
        path    = "/status/200",
        headers = {
          host = helpers.mock_upstream_host,
        }
      })
      assert.res_status(200, res)
      assert.equal("Hit", res.headers["X-Cache-Status"])
      assert.equal("200", res.headers[constants.HEADERS.UPSTREAM_STATUS])
    end)
  end)

  describe("is not injected with default configuration", function()
    lazy_setup(function()
      setup_db()

      assert(helpers.start_kong {
        nginx_conf = "spec/fixtures/custom_nginx.template",
      })
    end)

    lazy_teardown(function()
      if client then
        client:close()
      end

      helpers.stop_kong()
    end)

    it("", function()
      local client = helpers.proxy_client()
      local res = assert(client:send {
        method  = "GET",
        path    = "/status/200",
        headers = {
          host = helpers.mock_upstream_host,
        }
      })
      assert.res_status(200, res)
      assert.is_nil(res.headers[constants.HEADERS.UPSTREAM_STATUS])
    end)
  end)

  for _, buffered in ipairs{false, true} do
  describe("is injected with configuration [headers=X-Kong-Upstream-Status]" ..
           (buffered and "(buffered)" or ""), function()
    lazy_setup(function()
      local db = setup_db()

      if buffered then
        db.plugins:insert {
          name = "response-phase",
          config = {
          }
        }
      end

      assert(helpers.start_kong {
        nginx_conf = "spec/fixtures/custom_nginx.template",
        headers = "X-Kong-Upstream-Status",
        -- to see if the header is injected when response is buffered
        plugins = buffered and "bundled,response-phase,dummy,key-auth",
      })
    end)

    lazy_teardown(function()
      if client then
        client:close()
      end

      helpers.stop_kong()
    end)

    it("", function()
      local client = helpers.proxy_client()
      local res = assert(client:send {
        method  = "GET",
        path    = "/status/200",
        headers = {
          host = helpers.mock_upstream_host,
        }
      })
      assert.res_status(200, res)
      assert("200", res.headers[constants.HEADERS.UPSTREAM_STATUS])
    end)
  end)
  end

  describe("short-circuited requests", function()
    lazy_setup(function()
      setup_db()

      assert(helpers.start_kong {
        nginx_conf = "spec/fixtures/custom_nginx.template",
        headers = "X-Kong-Upstream-Status",
      })
    end)

    lazy_teardown(function()
      if client then
        client:close()
      end

      helpers.stop_kong()
    end)

    it("empty when rejected by authentication plugin", function()
      -- Added as a regression test during the merge of this patch to ensure
      -- the logic in the header_filter phase is defensive enough.
      -- As a result, the logic was moved within the `if proxied` branch.
      local client = helpers.proxy_client()
      local res = assert(client:send {
        method  = "GET",
        path    = "/status/non-proxied-request",
        headers = {
          host = helpers.mock_upstream_host,
        }
      })
      assert.res_status(401, res)
      assert.is_nil(res.headers[constants.HEADERS.UPSTREAM_STATUS])
    end)
  end)
end)
