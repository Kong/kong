local helpers = require "spec.helpers"
local cjson = require "cjson.safe"
local tablex = require "pl.tablex"


local function any(t, p)
  return #tablex.filter(t, p) > 0
end

local function post(client, path, body, headers, expected_status)
  headers = headers or {}
  if not headers["Content-Type"] then
    headers["Content-Type"] = "application/json"
  end

  if any(tablex.keys(body), function(x) return x:match( "%[%]$") end) then
    headers["Content-Type"] = "application/x-www-form-urlencoded"
  end

  local res = assert(client:send{
    method = "POST",
    path = path,
    body = body or {},
    headers = headers
  })

  return cjson.decode(assert.res_status(expected_status or 201, res))
end

local function delete(client, path, headers, expected_status)
  headers = headers or {}
  headers["Content-Type"] = "application/json"
  local res = assert(client:send{
    method = "DELETE",
    path = path,
    headers = headers
  })
  assert.res_status(expected_status or 204, res)
end


for _, strategy in helpers.each_strategy() do
  describe("CP/DP sync works with #" .. strategy .. " backend", function()

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
        db_update_frequency = 0.1,
        cluster_listen = "127.0.0.1:9005",
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      assert(helpers.start_kong({
        role = "data_plane",
        database = "off",
        prefix = "servroot2",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
        cluster_control_plane = "127.0.0.1:9005",
        proxy_listen = "0.0.0.0:9002",
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong("servroot2")
      helpers.stop_kong()
    end)

    it("syncs correctly the workspaces info", function()
      local function delayed_get(url, headers, expect)
        helpers.wait_until(function()
          local proxy_client = helpers.http_client("127.0.0.1", 9002)

          local res = proxy_client:get(url, { headers  = headers })

          local status = res and res.status
          proxy_client:close()
          if status == expect then
            return true
          end
        end, 10)
      end


      local admin_client = helpers.admin_client(10000)
      finally(function()
        admin_client:close()
      end)

      post(admin_client, "/workspaces/", { name = "ws1" })
      post(admin_client, "/ws1/services", { name = "mockbin-service-ws1", url = "https://127.0.0.1:15556/request", })
      post(admin_client, "/ws1/services/mockbin-service-ws1/routes", { name="rws1", paths = { "/ws1-route"}})
      post(admin_client, "/ws1/services/mockbin-service-ws1/plugins", {name = "key-auth"})
      post(admin_client, "/ws1/consumers", { username = "u1" })
      post(admin_client, "/ws1/consumers/u1/key-auth", { key = "u1" })
      -- post(admin_client, "/ws1/consumers/u1/key-auth", { key = "u2" })

      -- route/consumer is ok
      delayed_get("/ws1-route", { apikey= 'u1' }, 200)

      -- the key has to match
      delayed_get("/ws1-route", { apikey= 'foo' }, 401)

      -- shorter url doesn't match
      delayed_get("/", { apikey= 'u1' }, 404)

      -- default ws with a "/" route and a consumer with same creds
      post(admin_client, "/default/services", {name = "mockbin-service-default", url = "https://127.0.0.1:15556/request"})
      post(admin_client, "/default/services/mockbin-service-default/routes", {paths = { "/"}})
      post(admin_client, "/default/services/mockbin-service-default/plugins", {name = "key-auth"})
      post(admin_client, "/default/consumers", { username = "u1" })
      post(admin_client, "/default/consumers/u1/key-auth", { key = "u1" })

      -- route/consumer is ok
      delayed_get("/", { apikey= 'u1' }, 200)

      -- the key has to match
      delayed_get("/", { apikey= 'foo' }, 401)

      -- remove ws1 route to make sure we're matching the new one
      delete(admin_client, "/ws1/routes/rws1")

      -- match (but hopefully the one from default)
      delayed_get("/ws1-route", { apikey= 'u1' }, 200)
      delayed_get("/", { apikey= 'u1' }, 200)

      -- delete consumer from ws1
      delete(admin_client, "/ws1/consumers/u1/key-auth/u1")

      -- match, from consumer from default ws
      delayed_get("/", { apikey= 'u1' }, 200)

      -- add u2 key to ws1 consumer
      post(admin_client, "/ws1/consumers/u1/key-auth", { key = "u2" })

      -- doesn't work, wrong WS
      delayed_get("/", { apikey= 'u2' }, 401)
    end)
  end)
end
