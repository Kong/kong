local cassandra_strategy = require "kong.vitals.cassandra.strategy"
local dao_factory = require "kong.dao.factory"
local dao_helpers = require "spec.02-integration.03-dao.helpers"
local utils = require "kong.tools.utils"


dao_helpers.for_each_dao(function(kong_conf)
  if kong_conf.database == "postgres" then
    return
  end


  describe("Cassandra aggregator", function()
    local strategy
    local dao
    local cluster
    local uuid
    local hostname


    setup(function()
      dao      = assert(dao_factory.new(kong_conf))
      strategy = cassandra_strategy.new(dao)
      cluster  = dao.db.cluster
      uuid     = utils.uuid()
      hostname = "my_hostname"
    end)


    teardown(function()
      cluster:execute("TRUNCATE vitals_stats_seconds")
      cluster:execute("TRUNCATE vitals_stats_minutes")
      cluster:execute("TRUNCATE vitals_node_meta")
    end)


    describe(":init()", function()
      it("should record the node_id and hostname in vitals_node_meta", function()
        assert(strategy:init(uuid, hostname))
        local res, _ = cluster:execute("select * from vitals_node_meta")
        assert.same(res[1].node_id, uuid)
        assert.same(res[1].first_report, res[1].last_report)
        assert.same(res[1].hostname, hostname)
      end)
    end)


    describe(":insert_stats()", function()
      it("turns Lua tables into Cassandra rows", function()
        local now = ngx.time()
        local minute = math.floor(now / 60) * 60000
        local hour   = math.floor(now/ 3600) * 3600000

        stub(strategy, "get_minute").returns(minute)
        stub(strategy, "get_hour").returns(hour)

        local data = {
          { 1505964713, 0, 0, nil, nil },
          { 1505964714, 19, 99, 0, 120 },
        }

        assert(strategy:insert_stats(data, uuid))

        local seconds_res, _ = cluster:execute("select * from vitals_stats_seconds")
        local minutes_res, _ = cluster:execute("select * from vitals_stats_minutes")
        local expected_seconds = {
          {
            node_id  = uuid,
            at       = 1505964714000,
            minute   = minute,
            l2_hit   = 19,
            l2_miss  = 99,
            plat_min = 0,
            plat_max = 120,
          },
          {
            node_id  = uuid,
            at       = 1505964713000,
            minute   = minute,
            l2_hit   = 0,
            l2_miss  = 0,
          },
          meta = {
            has_more_pages = false
          },
          type = "ROWS",
        }

        local expected_minutes = {
          {
            node_id  = uuid,
            at       = minute,
            hour     = hour,
            l2_hit   = 19,
            l2_miss  = 99,
            plat_min = 0,
            plat_max = 120,
          },
          meta = {
            has_more_pages = false
          },
          type = "ROWS",
        }

        assert.same(expected_seconds, seconds_res)
        assert.same(expected_minutes, minutes_res)
      end)

      it("should update the last_report in the node_meta", function()
        local res, _ = cluster:execute("select * from vitals_node_meta")
        local old_first_report = res[1].first_report
        local old_last_report = 1509380787000

        assert(cluster:execute("UPDATE vitals_node_meta SET last_report = " .. old_last_report .. " WHERE node_id = " .. uuid))

        local data = {
          { 1505966000, 0, 0, nil, nil },
        }

        assert(strategy:insert_stats(data, uuid))

        local res, _ = cluster:execute("select * from vitals_node_meta")

        local new_last_report = res[1].last_report
        local new_first_report = res[1].first_report

        assert.are_not.equals(old_last_report, new_last_report)
        assert.same(new_first_report, old_first_report)
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
