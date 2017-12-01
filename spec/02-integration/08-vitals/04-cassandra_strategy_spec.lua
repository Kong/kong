local cassandra_strategy = require "kong.vitals.cassandra.strategy"
local dao_factory = require "kong.dao.factory"
local dao_helpers = require "spec.02-integration.03-dao.helpers"
local utils = require "kong.tools.utils"
local helpers      = require "spec.helpers"


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
      helpers.run_migrations()

      local opts = {
        ttl_seconds = 3600,
        ttl_minutes = 90000,
      }

      dao      = assert(dao_factory.new(kong_conf))
      strategy = cassandra_strategy.new(dao, opts)
      cluster  = dao.db.cluster
      uuid     = utils.uuid()
      hostname = "my_hostname"
    end)


    before_each(function()
      cluster:execute("TRUNCATE vitals_stats_seconds")
      cluster:execute("TRUNCATE vitals_stats_minutes")
      cluster:execute("TRUNCATE vitals_node_meta")
      cluster:execute("TRUNCATE vitals_consumers")
    end)

    teardown(function()
      cluster:execute("TRUNCATE vitals_stats_seconds")
      cluster:execute("TRUNCATE vitals_stats_minutes")
      cluster:execute("TRUNCATE vitals_node_meta")
      cluster:execute("TRUNCATE vitals_consumers")
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

        assert(strategy:init(uuid, hostname))
        assert(strategy:insert_stats(data))

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
        assert(strategy:init(uuid, hostname))

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
      -- uuid of first node is  defined in intial spec setup
      local node_2_uuid = utils.uuid()
      local node_3_uuid = utils.uuid()

      local node_1_data = {
        { 1505964713, 0, 0, nil, nil },
        { 1505964714, 30, 60, 1, 5 },
      }

      local node_2_data = {
        { 1505964713, 1, 15, 5, 10 },
        { 1505964714, 30, 75, nil, nil },
      }

      local node_3_data = {
        { 1505964713, 5, 60, 10, 25 },
        { 1505964714, 10, 20, 10, 15 },
      }

      local now = ngx.time()
      local minute = math.floor(now / 60) * 60000
      local hour   = math.floor(now/ 3600) * 3600000

      stub(strategy, "get_minute").returns(minute)
      stub(strategy, "get_hour").returns(hour)
      
      before_each(function()
        assert(strategy:init(uuid, hostname))
        assert(strategy:insert_stats(node_1_data))

        assert(strategy:init(node_2_uuid, hostname))
        assert(strategy:insert_stats(node_2_data))

        assert(strategy:init(node_3_uuid, hostname))
        assert(strategy:insert_stats(node_3_data))
      end)

      it("should return cluster level data for seconds", function()
        local expected = {
          {
            node_id  = "cluster",
            at       = 1505964713000,
            l2_hit   = 6,
            l2_miss  = 75,
            plat_max = 25,
            plat_min = 5,
          }, {
            node_id  = "cluster",
            at       = 1505964714000,
            l2_hit   = 70,
            l2_miss  = 155,
            plat_max = 15,
            plat_min = 1,
          }
        }

        local res, _ = strategy:select_stats("seconds", "cluster", nil)
        
        table.sort(res, function(a,b) 
          return a.at < b.at
        end)

        assert.same(expected, res)
      end)

      it("should return cluster level data for minutes", function()
        local expected = {
          {
            node_id  = "cluster",
            at       = minute,
            l2_hit   = 76,
            l2_miss  = 230,
            plat_max = 25,
            plat_min = 1,
          }
        }

        local res, _ = strategy:select_stats("minutes", "cluster", nil)

        assert.same(expected, res)
      end)

      it("should return node level seconds data for all nodes", function()
        local expected = {
          {
            at = 1505964713000,
            l2_hit = 0,
            l2_miss = 0,
            minute = minute,
            node_id = uuid
          }, {
            at = 1505964714000,
            l2_hit = 30,
            l2_miss = 60,
            minute = minute,
            node_id = uuid,
            plat_max = 5,
            plat_min = 1,
          }, {
            at = 1505964713000,
            l2_hit = 1,
            l2_miss = 15,
            minute = minute,
            node_id = node_2_uuid,
            plat_max = 10,
            plat_min = 5,
          }, {
            at = 1505964714000,
            l2_hit = 30,
            l2_miss = 75,
            minute = minute,
            node_id = node_2_uuid,
          }, {
            at = 1505964713000,
            l2_hit = 5,
            l2_miss = 60,
            minute = minute,
            node_id = node_3_uuid,
            plat_max = 25,
            plat_min = 10,
          }, {
            at = 1505964714000,
            l2_hit = 10,
            l2_miss = 20,
            minute = minute,
            node_id = node_3_uuid,
            plat_max = 15,
            plat_min = 10,
          },
          meta = {
            has_more_pages = false ,
          },
          type = 'ROWS',
        }

        table.sort(expected, function(a,b)
          if a.node_id == b.node_id then
            return a.at < b.at
          end
          return a.node_id < b.node_id
        end)


        local res, _ = strategy:select_stats("seconds", "nodes", nil)

        table.sort(res, function(a,b)
          if a.node_id == b.node_id then
            return a.at < b.at
          end
          return a.node_id < b.node_id
        end)

        assert.same(expected, res)
      end)

      it("should return node level minutes data for all nodes", function()
        local expected = {
          {
            at = minute,
            hour = hour,
            l2_hit = 31,
            l2_miss = 90,
            node_id = node_2_uuid,
            plat_max = 10,
            plat_min = 5,
          }, {
            at = minute,
            hour = hour,
            l2_hit = 30,
            l2_miss = 60,
            node_id = uuid,
            plat_max = 5,
            plat_min = 1,
          }, {
            at = minute,
            hour = hour,
            l2_hit = 15,
            l2_miss = 80,
            node_id = node_3_uuid,
            plat_max = 25,
            plat_min = 10,
          },
          meta = {
            has_more_pages = false
          },
          type = 'ROWS'
        }

        table.sort(expected, function(a,b)
          if a.node_id == b.node_id then
            return a.at < b.at
          end
          return a.node_id < b.node_id
        end)

        local res, _ = strategy:select_stats("minutes", "nodes", nil)

        table.sort(res, function(a,b)
          if a.node_id == b.node_id then
            return a.at < b.at
          end
          return a.node_id < b.node_id
        end)

        assert.same(expected, res)
      end)

      it("should return node specific seconds data for a requested node", function()
        local expected = {
          {
            at = 1505964713000,
            l2_hit = 0,
            l2_miss = 0,
            minute = minute,
            node_id = uuid
          }, {
            at = 1505964714000,
            l2_hit = 30,
            l2_miss = 60,
            minute = minute,
            node_id = uuid,
            plat_max = 5,
            plat_min = 1,
          },
          meta = {
            has_more_pages = false
          },
          type = 'ROWS'
        }

        local res, _ = strategy:select_stats("seconds", "nodes", uuid)

        table.sort(res, function(a,b)
          return a.at < b.at
        end)

        assert.same(expected, res)
      end)

      it("should return node specific minutes data for a requested node", function()
        local expected = {
          {
            at = minute,
            hour = hour,
            l2_hit = 30,
            l2_miss = 60,
            node_id = uuid,
            plat_max = 5,
            plat_min = 1,
          },
          meta = {
            has_more_pages = false
          },
          type = 'ROWS'
        }
        local res, _ = strategy:select_stats("minutes", "nodes", uuid)

        assert.same(expected, res)
      end)
    end)

    describe(":insert_consumer_stats()", function()
      it("inserts seconds and minutes consumer request counter data", function()
        assert(strategy:init(uuid, hostname))

        local consumer_uuid_1 = utils.uuid()
        local consumer_uuid_2 = utils.uuid()

        local now = ngx.time()
        local now_converted = now * 1000
        local minute = math.floor(now / 60) * 60000

        local data = {
          { consumer_uuid_1, now, 1, 1 },
          { consumer_uuid_2, now, 1, 1 },
        }
        

        assert(strategy:insert_consumer_stats(data))

        local consumers_res, _ = cluster:execute("select * from vitals_consumers")

        table.sort(consumers_res, function(a,b)
          if a.consumer_id == b.consumer_id then
            return a.duration < b.duration
          end
          return a.consumer_id < b.consumer_id
        end)

        local expected_consumers = {
          {
            consumer_id = consumer_uuid_1,
            count       = 1,
            duration    = 60,
            node_id     = uuid,
            start_at    = minute
          },
          {
            consumer_id = consumer_uuid_2,
            count       = 1,
            duration    = 60,
            node_id     = uuid,
            start_at    = minute
          },
          {
            consumer_id = consumer_uuid_1,
            count       = 1,
            duration    = 1,
            node_id     = uuid,
            start_at    = now_converted
          },
          {
            consumer_id = consumer_uuid_2,
            count       = 1,
            duration    = 1,
            node_id     = uuid,
            start_at    = now_converted
          },
          meta = {
            has_more_pages = false
          },
          type = "ROWS"
        }

        table.sort(expected_consumers, function(a,b)
          if a.consumer_id == b.consumer_id then
            return a.duration < b.duration
          end
          return a.consumer_id < b.consumer_id
        end)

        assert.same(expected_consumers, consumers_res)
      end)
    end)
  end)
end)
