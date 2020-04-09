local helpers = require "spec.helpers"
local cjson = require "cjson.safe"


for _, strategy in helpers.each_strategy() do
  describe("CP/DP sync works with #" .. strategy .. " backend", function()
    local proxy_client, client

    lazy_setup(function()
      helpers.get_db_utils(strategy, {
        "routes",
        "services",
      }) -- runs migrations

      assert(helpers.start_kong({
        role = "control_plane",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
        database = strategy,
      }))

      assert(helpers.start_kong({
        role = "data_plane",
        database = "off",
        prefix = "servroot2",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
      }))

      client = helpers.admin_client(10000)
      proxy_client = helpers.proxy_client()
    end)

    lazy_teardown(function()
      if client then client:close() end
      helpers.stop_kong("servroot2")
      helpers.stop_kong()
    end)

    describe("status API", function()
      it("shows DP status", function()
        helpers.wait_until(function()
          local res = assert(client:get("/clustering/status"))
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          for _, v in pairs(json) do
            if v.ip == "127.0.0.1" then
              return true
            end
          end
        end, 5)
      end)
    end)

    describe("sync works", function()
      local route_id

      it("proxy on DP follows CP config #flaky", function()
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

        helpers.wait_until(function()
          proxy_client = helpers.proxy_client()

          res = assert(proxy_client:send({
            method  = "GET",
            path    = "/",
          }))

          if res.status == 200 then
            return true
          end
        end, 5)
      end)

      it("cache invalidation works on config change #flaky", function()
        local res = assert(client:send({
          method = "DELETE",
          path   = "/routes/" .. route_id,
        }))
        assert.res_status(204, res)

        helpers.wait_until(function()
          proxy_client = helpers.proxy_client()

          res = assert(proxy_client:send({
            method  = "GET",
            path    = "/",
          }))

          -- should remove the route from DP immediately
          if res.status == 404 then
            return true
          end
        end, 5)
      end)
    end)
  end)
end
