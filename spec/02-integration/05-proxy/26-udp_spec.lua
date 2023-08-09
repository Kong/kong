local helpers = require "spec.helpers"
local atc_compat = require "kong.router.compat"


local UDP_PROXY_PORT = 26001


local function reload_router(flavor)
  _G.kong = {
    configuration = {
      router_flavor = flavor,
    },
  }

  helpers.setenv("KONG_ROUTER_FLAVOR", flavor)

  package.loaded["spec.helpers"] = nil
  package.loaded["kong.global"] = nil
  package.loaded["kong.cache"] = nil
  package.loaded["kong.db"] = nil
  package.loaded["kong.db.schema.entities.routes"] = nil
  package.loaded["kong.db.schema.entities.routes_subschemas"] = nil

  helpers = require "spec.helpers"

  helpers.unsetenv("KONG_ROUTER_FLAVOR")
end


local function gen_route(flavor, r)
  if flavor ~= "expressions" then
    return r
  end

  r.expression = atc_compat.get_expression(r)
  r.priority = tonumber(atc_compat._get_priority(r))

  r.sources = nil

  return r
end


for _, flavor in ipairs({ "traditional", "traditional_compatible", "expressions" }) do
for _, strategy in helpers.each_strategy() do

  describe("UDP Proxying [#" .. strategy .. ", flavor = " .. flavor .. "]", function()
    reload_router(flavor)

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
      })

      local service = assert(bp.services:insert {
        name = "udp-service",
        url = "udp://127.0.0.1:" .. helpers.mock_upstream_stream_port,
      })

      assert(bp.routes:insert(gen_route(flavor, {
        protocols = { "udp" },
        service = service,
        sources = { { ip = "127.0.0.1", }, }
      })))

      assert(helpers.start_kong {
        router_flavor = flavor,
        database = strategy,
        nginx_conf  = "spec/fixtures/custom_nginx.template",
        stream_listen = "127.0.0.1:" .. UDP_PROXY_PORT .. " udp",
      })

    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    it("proxies udp", function()
      local client = ngx.socket.udp()
      assert(client:setpeername("127.0.0.1", UDP_PROXY_PORT))

      assert(client:send("HELLO WORLD!\n"))
      local echo = assert(client:receive())

      assert.equal("HELLO WORLD!\n", echo)
    end)
  end)
end
end   -- for flavor
