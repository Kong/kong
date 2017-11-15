local helpers     = require "spec.helpers"
local dao_helpers = require "spec.02-integration.03-dao.helpers"
local dao_factory = require "kong.dao.factory"
local kong_vitals = require "kong.vitals"
local singletons  = require "kong.singletons"
local cjson       = require "cjson"
local time        = ngx.time


dao_helpers.for_each_dao(function(kong_conf)
  if kong_conf.database == "cassandra" then
    -- only supporting postgres right now
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
          local now = time()

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

            assert.same({ 0, 1, cjson.null, cjson.null }, json.stats[tostring(now)])
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
