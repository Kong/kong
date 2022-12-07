local helpers = require "spec.helpers"
local cjson = require "cjson"


local pairs = pairs
local type = type
local null = ngx.null


local function remove_nulls(tbl)
  for k,v in pairs(tbl) do
    if v == null then
      tbl[k] = nil
    elseif type(v) == "table" then
      tbl[k] = remove_nulls(v)
    end
  end
  return tbl
end


local headers = {
  ["Content-Type"] = "application/json"
}


for _, strategy in helpers.each_strategy() do
  describe("Admin API #" .. strategy, function()
    local admin_client
    local proxy_client

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      }, {
        "worker-events",
      })

      bp.plugins:insert({
        name = "worker-events",
      })

      bp.routes:insert({
        paths = { "/" }
      })

      assert(helpers.start_kong {
        database = strategy,
        db_update_frequency = 0.1,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "worker-events",
      })
    end)

    lazy_teardown(function()
      helpers.stop_kong(nil, true)
    end)

    before_each(function()
      admin_client = helpers.admin_client()
      proxy_client = helpers.proxy_client()
    end)

    after_each(function()
      if admin_client then
        admin_client:close()
      end

      if proxy_client then
        proxy_client:close()
      end
    end)

    describe("worker events", function()
      it("triggers create event on creation", function()
        local res = admin_client:post("/routes", {
          headers = headers,
          body    = {
            hosts = {
              "example.test",
            },
          },
        })

        local body = assert.res_status(201, res)
        local entity = remove_nulls(cjson.decode(body))

        res  = proxy_client:get("/")
        body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.same({
          operation = "create",
          entity    = entity,
        }, json)
      end)

      it("triggers update event with old entity on update", function()
        local res = admin_client:put("/routes/test-update", {
          headers = headers,
          body    = {
            hosts = {
              "example.test",
            },
          },
        })

        -- TODO: it should really be 201, but Kong's PUT has always been 200,
        --       we can change it later (as we now know the difference).
        local body = assert.res_status(200, res)
        local entity = remove_nulls(cjson.decode(body))

        res  = proxy_client:get("/")
        body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.same({
          operation = "create",
          entity    = entity,
        }, json)

        local old_entity = entity

        res = admin_client:patch("/routes/test-update", {
          headers = headers,
          body    = {
            hosts = {
              "example2.test",
            },
          },
        })

        body = assert.res_status(200, res)
        entity = remove_nulls(cjson.decode(body))

        res  = proxy_client:get("/")
        body = assert.res_status(200, res)

        local json = cjson.decode(body)

        assert.same({
          operation  = "update",
          entity     = entity,
          old_entity = old_entity,
        }, json)
      end)

      it("triggers update event with old entity on upsert", function()
        local res = admin_client:put("/routes/test-upsert", {
          headers = headers,
          body    = {
            hosts = {
              "example.test",
            },
          },
        })

        -- TODO: it should really be 201, but Kong's PUT has always been 200,
        --       we can change it later (as we now know the difference).
        local body = assert.res_status(200, res)
        local entity = remove_nulls(cjson.decode(body))

        res  = proxy_client:get("/")
        body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.same({
          operation = "create",
          entity    = entity,
        }, json)

        local old_entity = entity

        res = admin_client:put("/routes/test-upsert", {
          headers = headers,
          body    = {
            hosts = {
              "example2.test",
            },
          },
        })

        body = assert.res_status(200, res)
        entity = remove_nulls(cjson.decode(body))

        res  = proxy_client:get("/")
        body = assert.res_status(200, res)

        local json = cjson.decode(body)

        assert.same({
          operation  = "update",
          entity     = entity,
          old_entity = old_entity,
        }, json)
      end)

      it("triggers delete event on delete", function()
        local res = admin_client:put("/routes/test-delete", {
          headers = headers,
          body    = {
            hosts = {
              "example.test",
            },
          },
        })

        -- TODO: it should really be 201, but Kong's PUT has always been 200,
        --       we can change it later (as we now know the difference).
        local body = assert.res_status(200, res)
        local entity = remove_nulls(cjson.decode(body))

        res  = proxy_client:get("/")
        body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.same({
          operation = "create",
          entity    = entity,
        }, json)

        res = admin_client:delete("/routes/test-delete", {
          headers = headers,
        })

        assert.res_status(204, res)

        res  = proxy_client:get("/")
        body = assert.res_status(200, res)

        local json = cjson.decode(body)

        assert.same({
          operation = "delete",
          entity    = entity,
        }, json)
      end)
    end)
  end)
end
