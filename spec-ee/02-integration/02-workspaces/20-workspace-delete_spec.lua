-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local fmt = string.format
local helpers = require "spec.helpers"

local fixtures = {
  http_mock = {
    test = [[
      server {
          listen 12345;

          location ~ "/hello" {
            return 200;
          }

        }
    ]]
  }
}


local function init_workspace(bp, ws)
  local entities = {}

  local service = assert(bp.services:insert_ws({
    name = "example-service",
    url = "http://localhost:12345",
  }, ws))
  entities["services"] = { service }

  local route = assert(bp.routes:insert_ws({
    name = "example-route",
    paths = { "/ws2" },
    service = service,
  }, ws))
  entities["routes"] = { route }

  local plugin = assert(bp.plugins:insert_ws({
    name = "key-auth",
    route = route,
  }, ws))
  entities["plugins"] = { plugin }

  local consumer = assert(bp.consumers:insert_ws({
    username = "foo",
  }, ws))
  entities["consumers"] = { consumer }

  assert(bp.keyauth_credentials:insert_ws({
    key = "5SRmk6gLnTy1SyQ1Cl9GzoRXJbjYGGbZ",
    consumer = { id = consumer.id },
  }, ws))

  return entities
end


for _, strategy in helpers.each_strategy() do

  describe("workspace cascade delete #" .. strategy, function()
    local bp, db
    local admin_client, proxy_client
    local ws
    local cache_keys

    lazy_setup(function()
      bp, db = helpers.get_db_utils(strategy)

      local service = assert(bp.services:insert {
        url = "http://localhost:12345",
      })
      assert(bp.routes:insert {
        paths = { "/ws1" },
        service = service,
      })
      ws = assert(bp.workspaces:insert {
        name = "workspace1"
      })

      local entities = init_workspace(bp, ws)

      cache_keys = {
        db.workspaces:cache_key(ws.name),
        db.services:cache_key(entities.services[1].id, nil, nil, nil, nil, ws.id),
        db.keyauth_credentials:cache_key("5SRmk6gLnTy1SyQ1Cl9GzoRXJbjYGGbZ", nil, nil, nil, nil, ws.id),
        db.consumers:cache_key(entities.consumers[1].id, nil, nil, nil, nil, ws.id),
      }

      assert(helpers.start_kong({
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }, nil, nil, fixtures))

      admin_client = helpers.admin_client()
      proxy_client = helpers.proxy_client()

      -- verify the workspace exist
      local res = assert(admin_client:get("/workspaces/" .. ws.name))
      assert.res_status(200, res)
      local res = assert(admin_client:get("/" .. ws.name .. "/consumers/"))
      assert.res_status(200, res)

      -- verify the configuration works
      local res = proxy_client:get("/ws2/hello?apikey=5SRmk6gLnTy1SyQ1Cl9GzoRXJbjYGGbZ")
      assert.res_status(200, res)

      -- verify the caches exist
      for _, key in ipairs(cache_keys) do
        local res = assert(admin_client:get("/cache/" .. key))
        res:read_body()
        assert.equal(200, res.status, fmt("%s does not found", key))
      end

      -- cascade delete a workspace
      local res = assert(admin_client:delete("/workspaces/" .. ws.name .. "?cascade=true"))
      assert.res_status(204, res)

      local res = assert(admin_client:get("/workspaces/" .. ws.name))
      assert.res_status(404, res)
    end)

    lazy_teardown(function()
      helpers.stop_kong()
      if admin_client then
        admin_client:close()
      end
      if proxy_client then
        proxy_client:close()
      end
    end)


    it("workspace and its data should be deleted from database", function()
      local res = assert(db.connector:query("select table_name from information_schema.columns where column_name = 'ws_id'"))
      for _, e in ipairs(res) do
        local count = assert(db.connector:query(fmt("select count(*) as n from %s where ws_id = '%s'", e.table_name, ws.id)))
        assert.equal(0, count[1].n)
      end
    end)

    it("caches should be evicted", function()
      helpers.pwait_until(function()
        for _, key in ipairs(cache_keys) do
          local res = assert(admin_client:get("/cache/" .. key))
          res:read_body()
          assert.equal(404, res.status, fmt("%s still exist", key))
        end
        return true
      end, 5)
    end)

    it("router should be rebuilt", function()
      local res = proxy_client:get("/hello")
      local body = assert.res_status(404, res)
      assert.equal('{\n  "message":"no Route matched with those values"\n}', body)
    end)

    it("should not touch other workspaces", function()
      local res = proxy_client:get("/ws1/hello")
      assert.res_status(200, res)
    end)
  end)

  describe("clustering sync", function()
    local admin_client
    local ws
    local bp

    lazy_setup(function()
      bp = helpers.get_db_utils(strategy)

      local service = bp.services:insert {
        protocol = "http",
        host = helpers.mock_upstream_host,
        port = helpers.mock_upstream_port,
      }

      bp.routes:insert {
        hosts = { "example.com" },
        service = service
      }

      ws = assert(bp.workspaces:insert {
        name = "workspace2"
      })

      init_workspace(bp, ws)

      assert(helpers.start_kong({
        role = "control_plane",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        database = strategy,
        --db_update_frequency = 0.1,
        cluster_listen = "127.0.0.1:9005",
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }, nil, nil, nil))

      assert(helpers.start_kong({
        role = "data_plane",
        database = "off",
        prefix = "servroot2",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        cluster_control_plane = "127.0.0.1:9005",
        proxy_listen = "0.0.0.0:9002",
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }, nil, nil, fixtures))

      admin_client = helpers.admin_client()
    end)

    lazy_teardown(function()
      if admin_client then
        admin_client:close()
      end

      helpers.stop_kong("servroot2")
      helpers.stop_kong()
    end)

    it("DP should be notified after workspace is cascade deleted", function()
      local proxy_client = helpers.proxy_client(nil, 9002)

      -- configuration should work
      helpers.pwait_until(function()
        local res = proxy_client:get("/ws2/hello?apikey=5SRmk6gLnTy1SyQ1Cl9GzoRXJbjYGGbZ")
        assert.res_status(200, res)
        return true
      end, 30)

      -- cascade delete a workspace
      local res = assert(admin_client:delete("/workspaces/" .. ws.name .. "?cascade=true"))
      assert.res_status(204, res)

      local res = assert(admin_client:get("/workspaces/" .. ws.name))
      assert.res_status(404, res)

      -- DP needs to be notified after workspace was deleted
      helpers.pwait_until(function()
        local res = proxy_client:get("/hello")
        local body = assert.res_status(404, res)
        assert.equal('{\n  "message":"no Route matched with those values"\n}', body)
        return true
      end, 30)
    end)

  end)
end




