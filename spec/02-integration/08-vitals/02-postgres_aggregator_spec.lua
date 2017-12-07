local aggregator_m = require "kong.vitals.postgres.aggregator"
local dao_factory  = require "kong.dao.factory"
local helpers      = require "spec.helpers"
local dao_helpers  = require "spec.02-integration.03-dao.helpers"


dao_helpers.for_each_dao(function(kong_conf)
  if kong_conf.database == "cassandra" then
    return
  end

  describe("Postgres aggregator", function()
    local aggregator
    local dao
    local db
    local snapshot


    setup(function()
      helpers.run_migrations()

      dao = assert(dao_factory.new(kong_conf))
      db  = dao.db

      local opts = {
        db = db,
      }

      aggregator = aggregator_m.new(opts)
    end)


    before_each(function()
      snapshot = assert:snapshot()

      assert(db:query("create table if not exists vitals_stats_seconds_1 (like vitals_stats_seconds)"))
      assert(db:query("truncate table vitals_stats_seconds_1"))
      assert(db:query("truncate table vitals_stats_minutes"))
    end)


    after_each(function()
      snapshot:revert()
    end)


    describe(":aggregate_minutes()", function()
      before_each(function()
        -- add some seconds
        local insert_seconds = [[
        insert into vitals_stats_seconds_1 values
        ('{5b573229-565a-4264-b5f4-e0b42cff87b8}', 1505929137, 0, 0, null, null, null, null, 0),
        ('{5b573229-565a-4264-b5f4-e0b42cff87b8}', 1505929138, 0, 15, 0, 23, 4, 13, 4),
        ('{5b573229-565a-4264-b5f4-e0b42cff87b8}', 1505929139, 12, 2, 3, 8, 9, 86, 6),
        ('{5b573229-565a-4264-b5f4-e0b42cff87b8}', 1505929140, 1, 2, 3, 4, 12, 37, 7)
      ]]
        assert(db:query(insert_seconds))
      end)


      it("turns seconds into minutes", function()
        -- for this test, don't delete old minutes. These minutes _are_ old.
        stub(aggregator, "delete_before")


        aggregator:aggregate_minutes("vitals_stats_seconds_1")

        local res, _ = db:query("select * from vitals_stats_minutes")

        local expected = {
          {
            node_id  = "5b573229-565a-4264-b5f4-e0b42cff87b8",
            at       = 1505929080,
            l2_hit   = 12,
            l2_miss  = 17,
            plat_min = 0,
            plat_max = 23,
            ulat_min = 4,
            ulat_max = 86,
            requests = 10,
          },
          {
            node_id  = "5b573229-565a-4264-b5f4-e0b42cff87b8",
            at       = 1505929140,
            l2_hit   = 1,
            l2_miss  = 2,
            plat_min = 3,
            plat_max = 4,
            ulat_min = 12,
            ulat_max = 37,
            requests = 7,
          },
        }

        assert.same(expected, res)
      end)


      it("deletes old minutes", function()
        local old_minutes = [[
            insert into vitals_stats_minutes values
            ('{5b573229-565a-4264-b5f4-e0b42cff87b8}', 1505929137, 0, 0, null, null, null, null, 0),
            ('{5b573229-565a-4264-b5f4-e0b42cff87b8}', 1505929138, 0, 15, 0, 23, 4, 13, 4),
            ('{5b573229-565a-4264-b5f4-e0b42cff87b8}', 1505929139, 12, 2, 3, 8, 9, 86, 6),
            ('{5b573229-565a-4264-b5f4-e0b42cff87b8}', 1505929140, 1, 2, 3, 4, 12, 37, 7)
        ]]

        assert(db:query(old_minutes))

        assert(aggregator:aggregate_minutes("vitals_stats_seconds_1"))

        local res, _ = db:query("select * from vitals_stats_minutes where at <= 1503283560")

        assert.equal(0, #res)
      end)
    end)
  end)
end)
