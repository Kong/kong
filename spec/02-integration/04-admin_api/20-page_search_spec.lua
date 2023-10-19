-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson"
local pl_stringx = require "pl.stringx"
local fmt = string.format

for _, strategy in helpers.each_strategy({"postgres"}) do

local strategy = "postgres"

describe("Admin API - search", function()

  describe("/entities search with DB: #" .. strategy, function()
    local client, bp, db

    local test_entity_count = 100

    lazy_setup(function()
      bp, db = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "consumers",
        "vaults",
        "workspaces",
        }, nil, {
        "env"
      })

      for i = 1, test_entity_count do
        local route = {
          name = fmt("route%s", i),
          hosts = { fmt("example-%s.com", i) },
          paths = { fmt("/%s", i) },
        }
        local _, err, err_t = bp.routes:insert(route)
        assert.is_nil(err)
        assert.is_nil(err_t)

        local service = {
          name = fmt("service%s", i),
          enabled = true,
          protocol = "http",
          host = fmt("example-%s.com", i),
          path = fmt("/%s", i),
        }
        local service, err, err_t = bp.services:insert(service)
        assert.is_nil(err)
        assert.is_nil(err_t)

        local plugin = {
          name = "cors",
          instance_name = fmt("plugin%s", i),
          enabled = true,
          config = {},
          service = service,
        }
        local _, err, err_t = bp.plugins:insert(plugin)
        assert.is_nil(err)
        assert.is_nil(err_t)

        local vault = {
          name = "env",
          prefix = fmt("env-%s", i),
          description = fmt("description-%s", i)
        }
        local _, err, err_t = bp.vaults:insert(vault)
        assert.is_nil(err)
        assert.is_nil(err_t)
        
        local _, err, err_t = bp.workspaces:insert { name = "workspace-" .. i }
        assert.is_nil(err)
        assert.is_nil(err_t)

      end

      local consumers = {
        {
          username = "foo",
          custom_id = "bar",
        },
        {
          username = "foo2",
          custom_id = "bar2",
        },
        {
          username = "foo3",
          custom_id = "bar3",
        }
      }
      for _, consumer in pairs(consumers) do
        local _, err, err_t = bp.consumers:insert(consumer)
        assert.is_nil(err)
        assert.is_nil(err_t)
      end

      assert(helpers.start_kong {
        database = strategy,
      })
      client = assert(helpers.admin_client(10000))
    end)

    lazy_teardown(function()
      if client then client:close() end
      helpers.stop_kong()
    end)

    it("known field only", function()
      local err
      _, err = db.services:page(nil, nil, { search_fields = { wat = "wat" } })
      assert.same(err, "[postgres] invalid option (search_fields: cannot search on unindexed field 'wat')")
      _, err = db.services:page(nil, nil, { search_fields = { ["name;drop/**/table/**/services;/**/--/**/-"] = "1" } })
      assert.same(err, "[postgres] invalid option (search_fields: cannot search on unindexed field 'name;drop/**/table/**/services;/**/--/**/-')")
    end)

    it("common field", function()
      local res
      res = assert(client:send {
        method = "GET",
        path = "/services?name=100"
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same('service100', json.data[1].name)
      
      res = assert(client:send {
        method = "GET",
        path = "/services?size=100&sort_by=name&name="
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same(test_entity_count, #json.data)
      assert.same('service1', json.data[1].name)

      res = assert(client:send {
        method = "GET",
        path = "/routes?name=100"
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same('route100', json.data[1].name)
      
      res = assert(client:send {
        method = "GET",
        path = "/routes?size=100&sort_by=name&name="
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same(test_entity_count, #json.data)
      assert.same('route1', json.data[1].name)

      res = assert(client:send {
        method = "GET",
        path = "/routes?hosts=100"
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same('route100', json.data[1].name)

      res = assert(client:send {
        method = "GET",
        path = "/services?size=100&enabled=true"
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same(100, #json.data)

      res = assert(client:send {
        method = "GET",
        path = "/vaults?size=100&name=env"
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same(100, #json.data)

      res = assert(client:send {
        method = "GET",
        path = "/vaults?prefix=env-100"
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same('env-100', json.data[1].prefix)
      
      -- workspaces
      res = assert(client:send {
        method = "GET",
        path = "/workspaces?size=100"
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same(100, #json.data)
      
      res = assert(client:send {
        method = "GET",
        path = "/workspaces?size=200&sort_by=name"
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same(101, #json.data)
      assert.same("workspace-1", json.data[2].name)
      
      res = assert(client:send {
        method = "GET",
        path = "/workspaces?name=workspace-100"
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same('workspace-100', json.data[1].name)
      -- plugin
      res = assert(client:send {
        method = "GET",
        path = "/plugins?instance_name=plugin9"
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.equal(11, #json.data)
      for _, p in ipairs(json.data) do
        assert.is_true(pl_stringx.startswith(p.instance_name, "plugin9"))
      end
    end)

    it("array field", function()
      local res
      res = assert(client:send {
        method = "GET",
        path = "/routes?protocols=http"
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same(100, #json.data)

      res = assert(client:send {
        method = "GET",
        path = "/routes?protocols=https"
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same(100, #json.data)

      res = assert(client:send {
        method = "GET",
        path = "/routes?protocols=http,https"
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same(100, #json.data)

      res = assert(client:send {
        method = "GET",
        path = "/routes?protocols=http,https,grpc"
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same(0, #json.data)
    end)

    it("fuzzy field", function()
      local res
      res = assert(client:send {
        method = "GET",
        path = "/routes?hosts=100"
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same("route100", json.data[1].name)
    end)

    it("consumers multiple fields", function()
      local res
      res = assert(client:send {
        method = "GET",
        path = "/consumers?username=foo"
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same(3, #json.data)

      res = assert(client:send {
        method = "GET",
        path = "/consumers?custom_id=bar"
      })
      body = assert.res_status(200, res)
      json = cjson.decode(body)
      assert.same("foo", json.data[1].username)

      res = assert(client:send {
        method = "GET",
        path = "/consumers?custom_id=bar3"
      })
      body = assert.res_status(200, res)
      json = cjson.decode(body)
      assert.same("foo3", json.data[1].username)

      res = assert(client:send {
        method = "GET",
        path = "/consumers?username=error&custom_id=bar3"
      })
      body = assert.res_status(200, res)
      json = cjson.decode(body)
      assert.same(0, #json.data)
    end)

  end)

end)

end -- for _, strategy in helpers.each_strategy({"postgres"}) do
