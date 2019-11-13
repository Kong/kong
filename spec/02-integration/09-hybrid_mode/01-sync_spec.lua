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
        storage = strategy,
      }))

      assert(helpers.start_kong({
        role = "proxy",
        storage = "memory",
        prefix = "servroot2",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
      }))

      client = helpers.admin_client(10000)
      proxy_client = helpers.proxy_client()
    end)

    lazy_teardown(function()
      if client then client:close() end
      helpers.stop_kong("servroot2")
      helpers.stop_kong()
    end)

    describe("sync works", function()
      it("proxy on DP follows CP config", function()
        local res = assert(client:post("/services", {
          body = { name = "mockbin-service", url = "https://mockbin.org/get", },
          headers = {["Content-Type"] = "application/json"}
        }))
        local body = assert.res_status(201, res)
        local json = cjson.decode(body)

        res = assert(client:post("/services/mockbin-service/routes", {
          body = { paths = { "/", }, },
          headers = {["Content-Type"] = "application/json"}
        }))
        body = assert.res_status(201, res)

        ngx.sleep(1)

        res = assert(proxy_client:send({
          method  = "GET",
          path    = "/",
        }))
        body = assert.res_status(200, res)
        print(body)
      end)
    end)
  end)
end
