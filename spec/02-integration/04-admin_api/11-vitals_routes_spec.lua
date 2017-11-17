local helpers     = require "spec.helpers"
local dao_helpers = require "spec.02-integration.03-dao.helpers"
local dao_factory = require "kong.dao.factory"
local kong_vitals = require "kong.vitals"
local singletons  = require "kong.singletons"
local cjson       = require "cjson"
local time        = ngx.time


dao_helpers.for_each_dao(function(kong_conf)

  if kong_conf.database == "cassandra" then
    -- only test postgres currently
    return
  end

  describe("Admin API Vitals with " .. kong_conf.database, function()
    local client, dao, vitals

    describe("when vitals is enabled", function()
      setup(function()
        dao = assert(dao_factory.new(kong_conf))

        dao:truncate_tables()

        helpers.run_migrations(dao)

        singletons.configuration = { vitals = true }
        
        vitals = kong_vitals.new({
          dao = dao,
          flush_interval = 60,
          postgres_rotation_interval = 3600,
        })
        vitals:init()

        assert(helpers.start_kong({
          database = kong_conf.database,
          vitals   = true,
        }))

        client = helpers.admin_client()
      end)

      teardown(function()
        if client then
          client:close()
        end

        helpers.stop_kong()
      end)

      describe("/vitals", function()
        describe("GET", function()
          local now = time() + 1000

          before_each(function()
            assert(vitals.strategy:insert_stats({ { now, 0, 1 } }))
          end)

          it("retrieves the vitals data", function()
            local res = assert(client:send {
              methd = "GET",
              path = "/vitals"
            })
            res = assert.res_status(200, res)
            local json = cjson.decode(res)

            assert.same({ 0, 1, cjson.null, cjson.null }, json.stats.cluster[tostring(now)])
          end)
        end)
      end)

      describe("/vitals/cluster", function()
        describe("GET", function()
          local now = time() + 2000
          local minute = now - (now % 60)

          before_each(function()
            assert(vitals.strategy:insert_stats({ { now, 0, 1 } }))
          end)

          it("retrieves the vitals seconds cluster data", function()
            local res = assert(client:send {
              methd = "GET",
              path = "/vitals/cluster",
              query = {
                interval = 'seconds'
              }
            })
            res = assert.res_status(200, res)
            local json = cjson.decode(res)

            assert.same({ 0, 1, cjson.null, cjson.null }, json.stats.cluster[tostring(now)])
          end)

          pending("retrieves the vitals minutes cluster data", function()
            local res = assert(client:send {
              methd = "GET",
              path = "/vitals/cluster",
              query = {
                interval = 'minutes'
              }
            })
            res = assert.res_status(200, res)
            local json = cjson.decode(res)

            assert.same({ 0, 1, cjson.null, cjson.null }, json.stats.cluster[tostring(minute)])
          end)

          it("returns a 400 if called with invalid query param", function()
            local res = assert(client:send {
              methd = "GET",
              path = "/vitals/cluster",
              query = {
                interval = 'so-wrong'
              }
            })
            res = assert.res_status(400, res)
            local json = cjson.decode(res)

            assert.same("Invalid query params: interval must be 'minutes' or 'seconds'", json.message)
          end)
        end)
      end)

      describe("/vitals/nodes", function()
        describe("GET", function()
          local now = time() + 3000
          local minute = now - (now % 60)
          local node_id = vitals.shm:get("vitals:node_id")

          before_each(function()
            assert(vitals.strategy:insert_stats({ { now, 0, 1 } }))
          end)

          it("retrieves the vitals seconds data for all nodes", function()
            local res = assert(client:send {
              methd = "GET",
              path = "/vitals/nodes",
              query = {
                interval = 'seconds'
              }
            })
            res = assert.res_status(200, res)
            local json = cjson.decode(res)

            assert.same({ 0, 1, cjson.null, cjson.null }, json.stats[node_id][tostring(now)])
          end)

          pending("retrieves the vitals minutes data for all nodes", function()
            local res = assert(client:send {
              methd = "GET",
              path = "/vitals/nodes",
              query = {
                interval = 'minutes'
              }
            })
            res = assert.res_status(200, res)
            local json = cjson.decode(res)

            assert.same({ 0, 1, cjson.null, cjson.null }, json.stats[node_id][tostring(minute)])
          end)

          it("returns a 400 if called with invalid query param", function()
            local res = assert(client:send {
              methd = "GET",
              path = "/vitals/nodes",
              query = {
                interval = 'so-wrong'
              }
            })
            res = assert.res_status(400, res)
            local json = cjson.decode(res)

            assert.same("Invalid query params: interval must be 'minutes' or 'seconds'", json.message)
          end)
        end)
      end)

      describe("/vitals/nodes/{node_id}", function()
        describe("GET", function()
          local now = time() + 4000
          local minute = now - (now % 60)
          local node_id = vitals.shm:get("vitals:node_id")

          before_each(function()
            assert(vitals.strategy:insert_stats({ { now, 0, 1 } }))
          end)

          it("retrieves the vitals seconds data for a requested node", function()
            local res = assert(client:send {
              methd = "GET",
              path = "/vitals/nodes/" .. node_id,
              query = {
                interval = 'seconds'
              }
            })
            res = assert.res_status(200, res)
            local json = cjson.decode(res)

            assert.same({ 0, 1, cjson.null, cjson.null }, json.stats[node_id][tostring(now)])
          end)

          pending("retrieves the vitals minutes data for a requested node", function()
            local res = assert(client:send {
              methd = "GET",
              path = "/vitals/nodes/" .. node_id,
              query = {
                interval = 'minutes'
              }
            })
            res = assert.res_status(200, res)
            local json = cjson.decode(res)

            assert.same({ 0, 1, cjson.null, cjson.null }, json.stats[node_id][tostring(minute)])
          end)

          it("returns a 400 if called with invalid query param", function()
            local res = assert(client:send {
              methd = "GET",
              path = "/vitals/nodes/totally-fake-uuid",
              query = {
                interval = 'seconds'
              }
            })
            res = assert.res_status(400, res)
            local json = cjson.decode(res)

            assert.same("Invalid query params: invalid node_id", json.message)
          end)

          it("returns a 400 if called with invalid query param", function()
            local res = assert(client:send {
              methd = "GET",
              path = "/vitals/nodes/totally-fake-uuid",
              query = {
                interval = 'minutes'
              }
            })
            res = assert.res_status(400, res)
            local json = cjson.decode(res)

            assert.same("Invalid query params: invalid node_id", json.message)
          end)
        end)
      end)
    end)

    describe("when vitals is not enabled", function()
      setup(function()
        dao = assert(dao_factory.new(kong_conf))

        dao:truncate_tables()

        helpers.run_migrations(dao)

        vitals = kong_vitals.new({ dao = dao })

        assert(helpers.start_kong({
          database = kong_conf.database,
          vitals   = false,
        }))

        client = helpers.admin_client()
      end)

      teardown(function()
        if client then
          client:close()
        end

        helpers.stop_kong()
      end)

      describe("GET", function()

        it("responds 404", function()
          local res = assert(client:send {
            methd = "GET",
            path = "/vitals"
          })
          assert.res_status(404, res)
        end)
      end)
    end)
  end)

end)
