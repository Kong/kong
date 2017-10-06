local pg_strategy = require "kong.vitals.postgres.strategy"
local dao_factory = require "kong.dao.factory"
local helpers     = require "spec.helpers"
local dao_helpers = require "spec.02-integration.03-dao.helpers"


dao_helpers.for_each_dao(function(kong_conf)
  if kong_conf.database == "cassandra" then
    return
  end


  describe("Postgres aggregator", function()
    local strategy
    local dao
    local db
    local snapshot


    setup(function()
      helpers.run_migrations()

      dao      = assert(dao_factory.new(kong_conf))
      strategy = pg_strategy.new(dao)

      db  = dao.db
    end)


    before_each(function()
      snapshot = assert:snapshot()

      assert(db:query("truncate table vitals_stats_seconds"))
    end)


    after_each(function()
      snapshot:revert()
    end)


    describe(":insert_stats()", function()
      it("turns Lua tables into Postgres rows", function()
        stub(strategy, "current_table_name").returns("vitals_stats_seconds")


        local data = {
          { 1505964713, 0, 0, nil, nil },
          { 1505964714, 19, 99, 0, 120 },
        }

        assert(strategy:insert_stats(data))

        local res, _ = db:query("select * from vitals_stats_seconds")

        local expected = {
          {
            at       = 1505964713,
            l2_hit   = 0,
            l2_miss  = 0,
          },
          {
            at       = 1505964714,
            l2_hit   = 19,
            l2_miss  = 99,
            plat_min = 0,
            plat_max = 120,
          },
        }
        assert.same(expected, res)
      end)
    end)


    describe(":select_stats()", function()
      it("rejects invalid function arguments", function()
        local res, err = strategy.select_stats("foo")

        local expected = "query_type must be 'minutes' or 'seconds'"

        assert.is_nil(res)
        assert.same(expected, err)
      end)
    end)
  end)
end)
