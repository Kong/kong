-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"

for _, strategy in helpers.each_strategy() do
  describe("Status API #" .. strategy .. " with workspaces", function()
    local bp
    local client

    local upstream_default, upstream_ws1

    lazy_setup(function()
      local fixtures = {
        dns_mock = helpers.dns_mock.new()
      }
      fixtures.dns_mock:A {
        name = "custom_localhost",
        address = "127.0.0.1",
      }

      bp = helpers.get_db_utils(strategy, {
        "upstreams",
        "targets",
        "workspaces",
        "clustering_data_planes",
        "certificates",
      })

      upstream_default = bp.upstreams:insert {}

      bp.targets:insert {
        target = "api-1:80",
        weight = 10,
        upstream = { id = upstream_default.id },
      }

      local ws1 = assert( bp.workspaces:insert {
        name = "ws1",
      })

      upstream_ws1 = bp.upstreams:insert_ws({}, ws1)

      for i=1, 2 do
        bp.targets:insert_ws({
          target = string.format("api-%d:80", i),
          weight = 10 * i,
          upstream = { id = upstream_ws1.id },
        }, ws1)
      end

      assert(helpers.start_kong({
        database = strategy,
        role = "control_plane",
        nginx_conf = "spec/fixtures/custom_nginx.template",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        cluster_listen = "127.0.0.1:9005",
        lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
        prefix = "cp",
        db_update_frequency = 0.1,
      }, nil, nil, fixtures))

      assert(helpers.start_kong({
        status_listen = "127.0.0.1:9500",
        database = "off",
        role = "data_plane",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        cluster_control_plane = "127.0.0.1:9005",
        lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
        prefix = "dp",
      }, nil, nil, fixtures))
    end)

    lazy_teardown(function()
      assert(helpers.stop_kong("cp"))
      assert(helpers.stop_kong("dp"))
    end)

    before_each(function()
      client = assert(helpers.http_client("127.0.0.1", 9500, 20000))
    end)

    after_each(function()
      if client then client:close() end
    end)

    it("extracts workspace parameter for default ws", function()
      helpers.wait_until(function()
        local dp_conf = assert(helpers.get_running_conf("dp"))

        local f = io.open(dp_conf.prefix .. "/config.cache.json.gz", "r")

        if f then
          return true
        end
      end, 10)

      for _, append in ipairs({ "", "/" }) do
        local res = assert(client:send {
          method = "GET",
          path = "/default/upstreams/" .. upstream_default.name .. "/targets" .. append,
        })
        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()

        -- we got 1 active targets for this upstream
        assert.equal(1, #json.data)
      end
    end)

    it("extracts workspace parameter for custom ws", function()
      helpers.wait_until(function()
        local running_conf = assert(helpers.get_running_conf("dp"))

        local f = io.open(running_conf.prefix .. "/config.cache.json.gz", "r")

        if f then
          return true
        end
      end, 10)

      for _, append in ipairs({ "", "/" }) do
        local res = assert(client:send {
          method = "GET",
          path = "/ws1/upstreams/" .. upstream_ws1.name .. "/targets" .. append,
        })
        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()

        -- we got 1 active targets for this upstream
        assert.equal(2, #json.data)
      end
    end)

    it("doesn't confuse between workspaces", function()
      helpers.wait_until(function()
        local running_conf = assert(helpers.get_running_conf("dp"))

        local f = io.open(running_conf.prefix .. "/config.cache.json.gz", "r")

        if f then
          return true
        end
      end, 10)

      for _, append in ipairs({ "", "/" }) do
        local res = assert(client:send {
          method = "GET",
          path = "/ws1/upstreams/" .. upstream_default.name .. "/targets" .. append,
        })
        assert.response(res).has.status(404)

        res = assert(client:send {
          method = "GET",
          path = "/default/upstreams/" .. upstream_ws1.name .. "/targets" .. append,
        })
        assert.response(res).has.status(404)

        res = assert(client:send {
          method = "GET",
          path = "/upstreams/" .. upstream_ws1.name .. "/targets" .. append,
        })
        assert.response(res).has.status(404)
      end
    end)
  end)
end
