local helpers = require "spec.helpers"
local cjson = require "cjson.safe"


for _, strategy in helpers.each_strategy() do
  describe("CP/DP sync works with " .. strategy .. " backend", function()
    local proxy_client, client

    lazy_setup(function()
      helpers.get_db_utils(strategy, {
        "routes",
        "services",
      }) -- runs migrations

      assert(helpers.start_kong({
        role = "admin",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        lua_ssl_trusted_certificate = "../spec/fixtures/kong_clustering.crt",
        database = strategy,
      }))

      assert(helpers.start_kong({
        role = "proxy",
        database = "off",
        prefix = "servroot2",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        lua_ssl_trusted_certificate = "../spec/fixtures/kong_clustering.crt",
      }))

      client = helpers.admin_client(10000)
      proxy_client = helpers.proxy_client()

      ngx.sleep(0.5) -- wait for DP to connect
    end)

    lazy_teardown(function()
      if client then client:close() end
      helpers.stop_kong("servroot2")
      helpers.stop_kong()
    end)

    describe("status API", function()
      it("shows DP status", function()
        local res = assert(client:get("/clustering/status"))
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        local found = false

        for _, v in pairs(json) do
          if v.ip == "127.0.0.1" then
            found = true
          end
        end

        assert(found, "DP did not connect to CP in time")
      end)
    end)

    describe("sync works", function()
      local route_id

      it("proxy on DP follows CP config", function()
        local res = assert(client:post("/services", {
          body = { name = "mockbin-service", url = "https://mockbin.org/request", },
          headers = {["Content-Type"] = "application/json"}
        }))
        assert.res_status(201, res)

        res = assert(client:post("/services/mockbin-service/routes", {
          body = { paths = { "/" }, },
          headers = {["Content-Type"] = "application/json"}
        }))
        local body = assert.res_status(201, res)
        local json = cjson.decode(body)

        route_id = json.id

        res = assert(proxy_client:send({
          method  = "GET",
          path    = "/",
        }))
        assert.res_status(200, res)
      end)

      it("cache invalidation works on config change", function()
        local res = assert(client:send({
          method = "DELETE",
          path   = "/routes/" .. route_id,
        }))
        assert.res_status(204, res)

        res = assert(proxy_client:send({
          method  = "GET",
          path    = "/",
        }))

        -- should remove the route from DP immediately
        assert.res_status(404, res)
      end)
    end)
  end)
end
