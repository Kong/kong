-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local fmt = string.format
local cjson = require "cjson"
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

local function create_entities(client, uri, request_body)
  local res = assert(client:post(uri, {
    body = request_body,
    headers = { ["Content-Type"] = "application/json" }
  }))
  local res_body = assert.res_status(201, res)
  return cjson.decode(res_body)
end

local function init_workspace(client, ws)
  local entities = {}

  local data = create_entities(client, fmt("/%s/services", ws.name), {
    name = "example-service",
    url = "http://localhost:12345",
  })
  entities["servcies"] = { data }

  local data = create_entities(client, fmt("/%s/services/example-service/routes", ws.name), {
    name = "example-route",
    paths = { "/ws2" },
  })
  entities["routes"] = { data }

  local data = create_entities(client, fmt("/%s/routes/example-route/plugins", ws.name), {
    name = "key-auth",
  })
  entities["plugins"] = { data }

  local data = create_entities(client, fmt("/%s/consumers", ws.name), {
    username = "foo",
  })
  entities["consumers"] = { data }

  local data = create_entities(client, fmt("/%s/consumers/foo/key-auth", ws.name), {
    key = "5SRmk6gLnTy1SyQ1Cl9GzoRXJbjYGGbZ"
  })
  entities["plugins"][2] = data

  return entities
end


for _, strategy in helpers.each_strategy() do

  describe("workspace cascade delete #" .. strategy, function()
    local bp, db
    local admin_client
    local proxy_client
    local ws

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

      assert(helpers.start_kong({
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }, nil, nil, fixtures))

      admin_client = helpers.admin_client()
      proxy_client = helpers.proxy_client()
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

    it("cascade delete a non-empty workspace", function()
      local entities = init_workspace(admin_client, ws)

      -- configuration should work
      local res = proxy_client:get("/ws2/hello?apikey=5SRmk6gLnTy1SyQ1Cl9GzoRXJbjYGGbZ")
      assert.res_status(200, res)

      local cache_keys = {
        db.workspaces:cache_key(ws.name),
        db.workspaces:cache_key(ws.id),
        db.services:cache_key(entities.servcies[1].id, nil, nil, nil, nil, ws.id),
        db.keyauth_credentials:cache_key("5SRmk6gLnTy1SyQ1Cl9GzoRXJbjYGGbZ", nil, nil, nil, nil, ws.id),
        db.consumers:cache_key(entities.consumers[1].id, nil, nil, nil, nil, ws.id),
      }

      -- caches should exist
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

      helpers.pwait_until(function()
        -- caches should be evicted
        for _, key in ipairs(cache_keys) do
          local res = assert(admin_client:get("/cache/" .. key))
          res:read_body()
          assert.equal(404, res.status, fmt("%s still exist", key))
        end
        return true
      end, 5)

      -- router should be rebuilt
      local res = proxy_client:get("/hello")
      local body = assert.res_status(404, res)
      assert.equal('{\n  "message":"no Route matched with those values"\n}', body)

      -- workspace and its data should be deleted from database
      local res = assert(db.connector:query("select table_name from information_schema.columns where column_name = 'ws_id'"))
      for _, e in ipairs(res) do
        local count = assert(db.connector:query(fmt("select count(*) as n from %s where ws_id = '%s'", e.table_name, ws.id)))
        assert.equal(0, count[1].n)
      end

      -- should not touch other workspaces
      local res = proxy_client:get("/ws1/hello")
      assert.res_status(200, res)
    end)

  end)

  describe("clustering sync", function()
    local admin_client
    local ws

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy)

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
      init_workspace(admin_client, ws)

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




