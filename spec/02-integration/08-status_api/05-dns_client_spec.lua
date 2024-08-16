local helpers = require "spec.helpers"
local cjson = require "cjson"

local tcp_status_port = helpers.get_available_port()

for _, strategy in helpers.each_strategy() do
  describe("[#traditional] Status API - DNS client route with [#" .. strategy .. "]" , function()
    local client

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "upstreams",
        "targets",
      })

      local upstream = bp.upstreams:insert()
      bp.targets:insert({
        upstream = upstream,
        target = "_service._proto.srv.test",
      })

      assert(helpers.start_kong({
        database = strategy,
        status_listen = "127.0.0.1:" .. tcp_status_port,
        new_dns_client = "on",
      }))

      client = helpers.http_client("127.0.0.1", tcp_status_port, 20000)
    end)

    teardown(function()
      if client then
        client:close()
      end
      helpers.stop_kong()
    end)

    it("/status/dns - status code 200", function ()
      local res = assert(client:send {
        method = "GET",
        path = "/status/dns",
        headers = { ["Content-Type"] = "application/json" }
      })

      local body = assert.res_status(200 , res)
      local json = cjson.decode(body)

      assert(type(json.worker.id) == "number")
      assert(type(json.worker.count) == "number")

      assert(type(json.stats) == "table")
      assert(type(json.stats["127.0.0.1|A/AAAA"].runs) == "number")

      -- Wait for the upstream target to be updated in the background
      helpers.wait_until(function ()
        local res = assert(client:send {
          method = "GET",
          path = "/status/dns",
          headers = { ["Content-Type"] = "application/json" }
        })

        local body = assert.res_status(200 , res)
        local json = cjson.decode(body)
        return type(json.stats["_service._proto.srv.test|SRV"]) == "table"
      end, 5)
    end)
  end)

  describe("[#traditional] Status API - DNS client route with [#" .. strategy .. "]" , function()
    local client

    lazy_setup(function()
      helpers.get_db_utils(strategy)

      assert(helpers.start_kong({
        database = strategy,
        status_listen = "127.0.0.1:" .. tcp_status_port,
        new_dns_client = "off",
      }))

      client = helpers.http_client("127.0.0.1", tcp_status_port, 20000)
    end)

    teardown(function()
      if client then
        client:close()
      end
      helpers.stop_kong()
    end)

    it("/status/dns - status code 501", function ()
      local res = assert(client:send {
        method = "GET",
        path = "/status/dns",
        headers = { ["Content-Type"] = "application/json" }
      })

      local body = assert.res_status(501, res)
      local json = cjson.decode(body)
      assert.same("not implemented with the legacy DNS client", json.message)
    end)
  end)
end


-- hybrid mode

for _, strategy in helpers.each_strategy() do

  describe("[#hybrid] Status API - DNS client route with [#" .. strategy .. "]" , function()
    local client

    lazy_setup(function()
      helpers.get_db_utils(strategy) -- runs migrations

      assert(helpers.start_kong({
        role = "control_plane",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        database = strategy,
        cluster_listen = "127.0.0.1:9005",
        nginx_conf = "spec/fixtures/custom_nginx.template",
        new_dns_client = "on",
      }))

      assert(helpers.start_kong({
        role = "data_plane",
        database = "off",
        prefix = "servroot2",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        cluster_control_plane = "127.0.0.1:9005",
        proxy_listen = "0.0.0.0:9002",
        nginx_conf = "spec/fixtures/custom_nginx.template",
        status_listen = "127.0.0.1:" .. tcp_status_port,
        new_dns_client = "on",
      }))

      client = helpers.http_client("127.0.0.1", tcp_status_port, 20000)
    end)

    teardown(function()
      if client then
        client:close()
      end
      helpers.stop_kong("servroot2")
      helpers.stop_kong()
    end)

    it("/status/dns - status code 200", function ()
      local res = assert(client:send {
        method = "GET",
        path = "/status/dns",
        headers = { ["Content-Type"] = "application/json" }
      })

      local body = assert.res_status(200 , res)
      local json = assert(cjson.decode(body))
      assert(type(json.stats) == "table")
    end)

  end)
end
