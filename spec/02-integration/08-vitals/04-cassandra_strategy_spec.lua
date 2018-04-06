local cassandra_strategy = require "kong.vitals.cassandra.strategy"
local dao_factory = require "kong.dao.factory"
local dao_helpers = require "spec.02-integration.03-dao.helpers"
local utils = require "kong.tools.utils"
local fmt = string.format
local time = ngx.time
local cassandra = require "cassandra"


dao_helpers.for_each_dao(function(kong_conf)
  if kong_conf.database == "postgres" then
    return
  end


  describe("Cassandra strategy", function()
    local strategy
    local dao
    local cluster
    local uuid
    local hostname
    local snapshot


    setup(function()
      local opts = {
        ttl_seconds = 3600,
        ttl_minutes = 90000,
      }

      dao      = assert(dao_factory.new(kong_conf))
      dao:run_migrations()
      strategy = cassandra_strategy.new(dao, opts)
      cluster  = dao.db.cluster
      uuid     = utils.uuid()
      hostname = "my_hostname"
    end)


    before_each(function()
      snapshot = assert:snapshot()
      cluster:execute("TRUNCATE vitals_stats_seconds")
      cluster:execute("TRUNCATE vitals_stats_minutes")
      cluster:execute("TRUNCATE vitals_node_meta")
      cluster:execute("TRUNCATE vitals_consumers")
      cluster:execute("TRUNCATE vitals_code_classes_by_cluster")
    end)

    after_each(function()
      snapshot:revert()
    end)


    teardown(function()
      cluster:execute("TRUNCATE vitals_stats_seconds")
      cluster:execute("TRUNCATE vitals_stats_minutes")
      cluster:execute("TRUNCATE vitals_node_meta")
      cluster:execute("TRUNCATE vitals_consumers")
      cluster:execute("TRUNCATE vitals_code_classes_by_cluster")
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
        local data = {
          { 1505964713, 0, 0, nil, nil, nil, nil, 5000, 0, 0, 0, 0 },
          { 1505964714, 19, 99, 0, 120, 5, 50, 10000, 12, 414, 40, 671 },
        }

        assert(strategy:insert_stats(data, uuid))

        local seconds_res, _ = cluster:execute("select * from vitals_stats_seconds")

        local expected_seconds = {
          {
            node_id  = uuid,
            at       = 1505964714000,
            l2_hit   = 19,
            l2_miss  = 99,
            plat_min = 0,
            plat_max = 120,
            ulat_min = 5,
            ulat_max = 50,
            requests = 10000,
            plat_count = 12,
            plat_total = 414,
            ulat_count = 40,
            ulat_total = 671,
          },
          {
            node_id  = uuid,
            at       = 1505964713000,
            l2_hit   = 0,
            l2_miss  = 0,
            requests = 5000,
            plat_count = 0,
            plat_total = 0,
            ulat_count = 0,
            ulat_total = 0,
          },
          meta = {
            has_more_pages = false
          },
          type = "ROWS",
        }

        assert.same(expected_seconds, seconds_res)

        local expected_minutes = {
          node_id = uuid,
          at = 1505964660000,
          l2_hit = 19,
          l2_miss = 99,
          plat_min = 0,
          plat_max = 120,
          ulat_min = 5,
          ulat_max = 50,
          requests = 15000,
          plat_count = 12,
          plat_total = 414,
          ulat_count = 40,
          ulat_total = 671,
        }

        local minutes_res, _ = cluster:execute("select * from vitals_stats_minutes")
        assert.same(expected_minutes, minutes_res[1])
      end)

      it("should not overwrite an existing seconds row", function()
        local firstInsert = {
          { 1505965513, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110 },
        }

        local secondInsert = {
          { 1505965513, 1000, 1000, 1000, 1000, 1000, 1000, 1000, 1000, 1000, 1000, 1000 },
        }

        local expected_seconds = {
          {
            node_id  = uuid,
            at       = 1505965513000,
            l2_hit   = 10,
            l2_miss  = 20,
            plat_min = 30,
            plat_max = 40,
            ulat_min = 50,
            ulat_max = 60,
            requests = 70,
            plat_count = 80,
            plat_total = 90,
            ulat_count = 100,
            ulat_total = 110,
          },
          meta = {
            has_more_pages = false
          },
          type = "ROWS",
        }

        assert(strategy:init(uuid, hostname))
        local s_insert_minutes = spy.on(strategy, "insert_minutes")

        assert(strategy:insert_stats(firstInsert))
        assert(strategy:insert_stats(secondInsert))
        assert.spy(s_insert_minutes).was_called(2)

        local seconds_res, _ = cluster:execute("select * from vitals_stats_seconds")
        assert.same(seconds_res, expected_seconds)
      end)

      it("should continue to insert minutes if seconds insert fails", function()
        local way_too_big = 0xFFFFFFFF + 1

        local firstInsert = {
          { 1505965513, way_too_big, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110 },
        }

        assert(strategy:init(uuid, hostname))
        local s_insert_minutes = spy.on(strategy, "insert_minutes")

        assert(strategy:insert_stats(firstInsert))
        assert.spy(s_insert_minutes).was_called()
      end)

      it("should not insert sentinel values (minutes)", function()
        local data = {
          { 1505964713, 1, 2, nil, nil, nil, nil, 5000, 10, 100, 20, 200 },
          { 1505964714, 3, 4, nil, nil, nil, nil, 10000, 5, 50, 15, 150 },
        }

        assert(strategy:insert_stats(data, uuid))

        local expected = {
          node_id = uuid,
          at = 1505964660000,
          l2_hit = 4,
          l2_miss = 6,
          plat_min = nil,
          plat_max = nil,
          ulat_min = nil,
          ulat_max = nil,
          requests = 15000,
          plat_count = 15,
          plat_total = 150,
          ulat_count = 35,
          ulat_total = 350,
        }
        local minutes_res, _ = cluster:execute("select * from vitals_stats_minutes")
        assert.same(expected, minutes_res[1])
      end)

      it("should update the last_report in the node_meta", function()
        assert(strategy:init(uuid, hostname))

        local res, _ = cluster:execute("select * from vitals_node_meta")
        local old_first_report = res[1].first_report
        local old_last_report = 1509380787000

        assert(cluster:execute("UPDATE vitals_node_meta SET last_report = " .. old_last_report .. " WHERE node_id = " .. uuid))

        local data = {
          { 1505966000, 0, 0, nil, nil, nil, nil, 0, 0, 0, 0, 0 },
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
      local node_1_uuid = utils.uuid()
      local node_2_uuid = utils.uuid()
      local node_3_uuid = utils.uuid()

      local now = ngx.time()

      local minute = now - now % 60

      local node_1_data = {
        { now - 1, 30, 60, 1, 5, nil, nil,   500, 5, 50, 0, 0 },
        { now,      0,  0, nil, nil, 5, 10, 1000, 0, 0, 20, 200 },
      }

      local node_2_data = {
        { now - 1, 30, 75, nil, nil, 30, 40, 5000, 0, 0, 4, 40 },
        { now,      1, 15, 5,    10, 20, 30, 2000, 1, 10, 2, 20 },
      }

      local node_3_data = {
        { now - 1, 10, 20, 10, 15, nil, nil,    5, 7, 70, 0, 0 },
        { now,      5, 60, 10, 25, 1, 2,      100, 5, 50, 6, 60 },
      }

      before_each(function()
        assert(strategy:init(node_1_uuid, hostname))
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
            at       = now,
            l2_hit   = 6,
            l2_miss  = 75,
            plat_min = 5,
            plat_max = 25,
            ulat_min = 1,
            ulat_max = 30,
            requests = 3100,
            plat_count = 6,
            plat_total = 60,
            ulat_count = 28,
            ulat_total = 280,
          },
          {
            node_id  = "cluster",
            at       = (now - 1),
            l2_hit   = 70,
            l2_miss  = 155,
            plat_min = 1,
            plat_max = 15,
            ulat_min = 30,
            ulat_max = 40,
            requests = 5505,
            plat_count = 12,
            plat_total = 120,
            ulat_count = 4,
            ulat_total = 40,
          },
        }

        local res, _ = strategy:select_stats("seconds", "cluster", nil)
        table.sort(res, function(a,b)
          return a.at > b.at
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
            plat_min = 1,
            plat_max = 25,
            ulat_min = 1,
            ulat_max = 40,
            requests = 8605,
            plat_count = 18,
            plat_total = 180,
            ulat_count = 32,
            ulat_total = 320,
          }
        }

        local res, _ = strategy:select_stats("minutes", "cluster", nil)
        assert.same(expected, res)
      end)

      it("should return node level seconds data for all nodes", function()
        local expected = {
          {
            at = (now - 1),
            l2_hit = 30,
            l2_miss = 60,
            node_id = node_1_uuid,
            plat_min = 1,
            plat_max = 5,
            requests = 500,
            plat_count = 5,
            plat_total = 50,
            ulat_count = 0,
            ulat_total = 0,
          },
          {
            at = now,
            l2_hit = 0,
            l2_miss = 0,
            node_id = node_1_uuid,
            ulat_min = 5,
            ulat_max = 10,
            requests = 1000,
            plat_count = 0,
            plat_total = 0,
            ulat_count = 20,
            ulat_total = 200,
          },
          {
            at = (now - 1),
            l2_hit = 10,
            l2_miss = 20,
            node_id = node_3_uuid,
            plat_min = 10,
            plat_max = 15,
            requests = 5,
            plat_count = 7,
            plat_total = 70,
            ulat_count = 0,
            ulat_total = 0,
          },
          {
            at = now,
            l2_hit = 5,
            l2_miss = 60,
            node_id = node_3_uuid,
            plat_min = 10,
            plat_max = 25,
            ulat_min = 1,
            ulat_max = 2,
            requests = 100,
            plat_count = 5,
            plat_total = 50,
            ulat_count = 6,
            ulat_total = 60,
          },
          {
            at = (now - 1),
            l2_hit = 30,
            l2_miss = 75,
            node_id = node_2_uuid,
            ulat_min = 30,
            ulat_max = 40,
            requests = 5000,
            plat_count = 0,
            plat_total = 0,
            ulat_count = 4,
            ulat_total = 40,
          },
          {
            at = now,
            l2_hit = 1,
            l2_miss = 15,
            node_id = node_2_uuid,
            plat_min = 5,
            plat_max = 10,
            ulat_min = 20,
            ulat_max = 30,
            requests = 2000,
            plat_count = 1,
            plat_total = 10,
            ulat_count = 2,
            ulat_total = 20,
          }
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
            l2_hit = 31,
            l2_miss = 90,
            node_id = node_2_uuid,
            plat_min = 5,
            plat_max = 10,
            ulat_min = 20,
            ulat_max = 40,
            requests = 7000,
            plat_count = 1,
            plat_total = 10,
            ulat_count = 6,
            ulat_total = 60,
          }, {
            at = minute,
            l2_hit = 30,
            l2_miss = 60,
            node_id = node_1_uuid,
            plat_min = 1,
            plat_max = 5,
            ulat_min = 5,
            ulat_max = 10,
            requests = 1500,
            plat_count = 5,
            plat_total = 50,
            ulat_count = 20,
            ulat_total = 200,
          }, {
            at = minute,
            l2_hit = 15,
            l2_miss = 80,
            node_id = node_3_uuid,
            plat_min = 10,
            plat_max = 25,
            ulat_min = 1,
            ulat_max = 2,
            requests = 105,
             plat_count = 12,
            plat_total = 120,
            ulat_count = 6,
            ulat_total = 60,
          },
        }

        table.sort(expected, function(a,b)
          if a.node_id == b.node_id then
            return a.at < b.at
          end
          return a.l2_hit > b.l2_hit
        end)

        local res, _ = strategy:select_stats("minutes", "nodes", nil)

        table.sort(res, function(a,b)
          if a.node_id == b.node_id then
            return a.at < b.at
          end
          return a.l2_hit > b.l2_hit
        end)

        assert.same(expected, res)
      end)

      it("should return node specific seconds data for a requested node", function()
        local expected = {
          {
            at = (now - 1),
            l2_hit = 30,
            l2_miss = 60,
            plat_min = 1,
            plat_max = 5,
            requests = 500,
            node_id = node_1_uuid,
            plat_count = 5,
            plat_total = 50,
            ulat_count = 0,
            ulat_total = 0,
          }, {
            at = now,
            l2_hit = 0,
            l2_miss = 0,
            node_id = node_1_uuid,
            ulat_min = 5,
            ulat_max = 10,
            requests = 1000,
            plat_count = 0,
            plat_total = 0,
            ulat_count = 20,
            ulat_total = 200,
          }
        }

        local res, _ = strategy:select_stats("seconds", "nodes", node_1_uuid)

        table.sort(res, function(a,b)
          return a.at < b.at
        end)

        assert.same(expected, res)
      end)

      it("should return node specific minutes data for a requested node", function()
        local expected = {
          {
            at = minute,
            l2_hit = 30,
            l2_miss = 60,
            node_id = node_1_uuid,
            plat_min = 1,
            plat_max = 5,
            ulat_min = 5,
            ulat_max = 10,
            requests = 1500,
            plat_count = 5,
            plat_total = 50,
            ulat_count = 20,
            ulat_total = 200,
          },
        }
        local res, _ = strategy:select_stats("minutes", "nodes", node_1_uuid)

        assert.same(expected, res)
      end)
    end)

    describe(":select_phone_home()", function()
      local node_1_uuid = utils.uuid()
      local node_2_uuid = utils.uuid()
      local node_3_uuid = utils.uuid()

      local now = ngx.time()

      local node_1_data = {
        { now, 0, 0, nil, nil, 5, 10, 1000, 10, 100, 19, 200 },
        { now - 1, 30, 60, 1, 5, nil, nil, 500, 6, 50, 13, 150 },
      }

      local node_2_data = {
        { now, 1, 15, 5, 10, 20, 30, 2000, 1, 10, 2, 20 },
        { now - 1, 30, 75, nil, nil, 30, 40, 5000, 3, 30, 4, 40 },
      }

      local node_3_data = {
        { now, 5, 60, 10, 25, 1, 2, 100, 5, 50, 6, 60 },
        { now - 1, 10, 20, 10, 15, nil, nil, 5, 7, 70, 8, 80 },
      }

      before_each(function()
        -- init the db so we have access to version info
        assert(dao.db:init())

        assert(strategy:init(node_1_uuid, hostname))
        assert(strategy:insert_stats(node_1_data))

        assert(strategy:insert_stats(node_2_data, node_2_uuid))

        assert(strategy:insert_stats(node_3_data, node_3_uuid))
      end)

      it("returns phone home stats", function()
        local expected = {{}}
        expected[1]["v.cdht"] = 30
        expected[1]["v.cdmt"] = 60
        expected[1]["v.lprn"] = 1
        expected[1]["v.lprx"] = 5
        expected[1]["v.lun"] = 5
        expected[1]["v.lux"] = 10

        if tonumber(dao.db:infos().version) >= 3 then
          expected[1]["v.nt"] = 3
        else
          -- 2.x can't do the node count query. Per PO, leave it out
          expected[1]["v.nt"] = nil
        end

        -- test data is set up to test rounding down: 150 / 16 = 9.375
        expected[1]["v.lpra"] = 9

        -- test data is set up to test rounding up: 350 / 32 = 10.9375
        expected[1]["v.lua"] = 11

        local res, err = strategy:select_phone_home()
        assert.is_nil(err)
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
            at          = minute
          },
          {
            consumer_id = consumer_uuid_2,
            count       = 1,
            duration    = 60,
            node_id     = uuid,
            at          = minute
          },
          {
            consumer_id = consumer_uuid_1,
            count       = 1,
            duration    = 1,
            node_id     = uuid,
            at           = now_converted
          },
          {
            consumer_id = consumer_uuid_2,
            count       = 1,
            duration    = 1,
            node_id     = uuid,
            at          = now_converted
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

    describe(":select_consumer_stats()", function()
      local node_1  = "20426633-55dc-4050-89ef-2382c95a611e"
      local node_2  = "8374682f-17fd-42cb-b1dc-7694d6f65ba0"
      local cons_id = utils.uuid()

      -- data starts a couple minutes ago
      local start_at = time() - 90
      local start_minute = start_at - (start_at % 60)

      before_each(function()
        local node_1_data = {
          {cons_id, start_at,      1, 1},
          {cons_id, start_at + 1,  1, 3},
          {cons_id, start_at + 2,  1, 4},
          {cons_id, start_at + 60, 1, 7},
          {cons_id, start_at + 61, 1, 11},
          {cons_id, start_at + 62, 1, 18},
        }

        local node_2_data = {
          {cons_id, start_at + 2,  1, 2},
          {cons_id, start_at + 60, 1, 5},
          {cons_id, start_at + 61, 1, 6},
          {cons_id, start_at + 62, 1, 8},
          {cons_id, start_at + 63, 1, 9},
        }

        assert(strategy:insert_consumer_stats(node_1_data, node_1))
        assert(strategy:insert_consumer_stats(node_2_data, node_2))
      end)

      after_each(function()
        cluster:execute("TRUNCATE vitals_consumers")
      end)

      it("validates arguments", function()
        local opts = {
          consumer_id = cons_id,
          node_id     = nil,
          duration    = "seconds",
          level       = "cluster",
        }

        local _, err = strategy:select_consumer_stats(opts)

        assert.is_nil(_)
        assert.same("duration must be 1 or 60", err)
      end)

      it("returns seconds stats for a consumer across the cluster", function()
        local opts = {
          consumer_id = cons_id,
          node_id     = nil,
          duration    = 1,
          level       = "cluster",
        }

        local results, _ = strategy:select_consumer_stats(opts)

        local expected = {
          {
            node_id     = "cluster",
            at          = start_at,
            count       = 1,
          },
          {
            node_id     = "cluster",
            at          = start_at + 1,
            count       = 3,
          },
          {
            node_id     = "cluster",
            at          = start_at + 2,
            count       = 6,
          },
          {
            node_id     = "cluster",
            at          = start_at + 60,
            count       = 12,
          },
          {
            node_id     = "cluster",
            at          = start_at + 61,
            count       = 17,
          },
          {
            node_id     = "cluster",
            at          = start_at + 62,
            count       = 26,
          },
          {
            node_id     = "cluster",
            at          = start_at + 63,
            count       = 9,
          },
        }

        assert.same(expected, results)
      end)


      it("returns seconds stats for a consumer and all nodes", function()
        local opts = {
          consumer_id = cons_id,
          node_id     = nil,
          duration    = 1,
          level       = "node",
        }

        local results, _ = strategy:select_consumer_stats(opts)

        -- just to make it easier to assert
        table.sort(results, function(a,b)
          return a.count < b.count
        end)

        local expected = {
          {
            node_id = node_1,
            at = start_at,
            count = 1,
          },
          {
            node_id = node_2,
            at = start_at + 2,
            count = 2,
          },
          {
            node_id = node_1,
            at = start_at + 1,
            count = 3,
          },
          {
            node_id = node_1,
            at = start_at + 2,
            count = 4,
          },
          {
            node_id = node_2,
            at = start_at + 60,
            count = 5,
          },
          {
            node_id = node_2,
            at = start_at + 61,
            count = 6,
          },
          {
            node_id = node_1,
            at = start_at + 60,
            count = 7,
          },
          {
            node_id = node_2,
            at = start_at + 62,
            count = 8,
          },
          {
            node_id = node_2,
            at = start_at + 63,
            count = 9,
          },
          {
            node_id = node_1,
            at = start_at + 61,
            count = 11,
          },
          {
            node_id = node_1,
            at = start_at + 62,
            count = 18,
          },
        }

        assert.same(expected, results)
      end)


      it("returns seconds stats for a consumer and a node", function()
        local opts = {
          consumer_id = cons_id,
          node_id     = node_2,
          duration    = 1,
          level       = "node",
        }

        local results, _ = strategy:select_consumer_stats(opts)

        local expected = {
          {
            node_id = node_2,
            at = start_at + 2,
            count = 2,
          },
          {
            node_id = node_2,
            at = start_at + 60,
            count = 5,
          },
          {
            node_id = node_2,
            at = start_at + 61,
            count = 6,
          },
          {
            node_id = node_2,
            at = start_at + 62,
            count = 8,
          },
          {
            node_id = node_2,
            at = start_at + 63,
            count = 9,
          },
        }

        assert.same(expected, results)
      end)


      it("returns minutes stats for a consumer across the cluster", function()
        local opts = {
          consumer_id = cons_id,
          node_id     = nil,
          duration    = 60,
          level       = "cluster",
        }

        local results, _ = strategy:select_consumer_stats(opts)

        local expected = {
          {
            node_id     = "cluster",
            at          = start_minute,
            count       = 10,
          },
          {
            node_id     = "cluster",
            at          = start_minute + 60,
            count       = 64,
          },
        }
        assert.same(expected, results)
      end)


      it("returns minutes stats for a consumer and all nodes", function()
        local opts = {
          consumer_id = cons_id,
          node_id     = nil,
          duration    = 60,
          level       = "node",
        }

        local results, _ = strategy:select_consumer_stats(opts)

        table.sort(results, function(a,b)
          return a.count < b.count
        end)


        local expected = {
          {
            node_id = node_2,
            at = start_minute,
            count = 2,
          },
          {
            node_id = node_1,
            at = start_minute,
            count = 8,
          },
          {
            node_id = node_2,
            at = start_minute + 60,
            count = 28,
          },
          {
            node_id = node_1,
            at = start_minute + 60,
            count = 36,
          },
        }

        assert.same(expected, results)
      end)


      it("returns minutes stats for a consumer and a node", function()
        local opts = {
          consumer_id = cons_id,
          node_id     = node_2,
          duration    = 60,
          level       = "node",
        }

        local results, _ = strategy:select_consumer_stats(opts)

        local expected = {
          {
            count = 2,
            node_id = node_2,
            at = start_minute,
          },
          {
            count = 28,
            node_id = node_2,
            at = start_minute + 60,
          },
        }

        assert.is_nil(_)
        assert.same(expected, results)
      end)
    end)

    describe(":delete_consumer_stats()", function()
      local cons_1 = "20426633-55dc-4050-89ef-2382c95a611e"
      local cons_2 = "8374682f-17fd-42cb-b1dc-7694d6f65ba0"
      local node_1 = utils.uuid()

      before_each(function()
        cluster:execute("TRUNCATE vitals_consumers")
        local q = "UPDATE vitals_consumers SET count=count+? WHERE consumer_id=? AND node_id=? AND at=? AND duration=?"

        local test_data = {
          {cassandra.counter(1), cassandra.uuid(cons_1), cassandra.uuid(node_1), cassandra.timestamp(1510560000000), 1},
          {cassandra.counter(3), cassandra.uuid(cons_1), cassandra.uuid(node_1), cassandra.timestamp(1510560001000), 1},
          {cassandra.counter(4), cassandra.uuid(cons_1), cassandra.uuid(node_1), cassandra.timestamp(1510560002000), 1},
          {cassandra.counter(19), cassandra.uuid(cons_1), cassandra.uuid(node_1), cassandra.timestamp(1510560000000), 60},
          {cassandra.counter(5), cassandra.uuid(cons_2), cassandra.uuid(node_1), cassandra.timestamp(1510560001000), 1},
          {cassandra.counter(7), cassandra.uuid(cons_2), cassandra.uuid(node_1), cassandra.timestamp(1510560002000), 1},
          {cassandra.counter(20), cassandra.uuid(cons_2), cassandra.uuid(node_1), cassandra.timestamp(1510560000000), 60},
          {cassandra.counter(24), cassandra.uuid(cons_2), cassandra.uuid(node_1), cassandra.timestamp(1510560060000), 60},
        }

        for _, row in ipairs(test_data) do
          assert(cluster:execute(q, row, { prepared = true, counter  = true }))
        end

        local res, _ = cluster:execute("select * from vitals_consumers")
        assert.same(8, #res)
      end)

      after_each(function()
        cluster:execute("TRUNCATE vitals_consumers")
      end)

      it("cleans up consumer stats", function()
        local consumers = {
          [cons_1] = true,
          [cons_2] = true,
        }

        -- query is "<" so bump the cutoff by a second
        local cutoff_times = {
          minutes = 1510560001,
          seconds = 1510560002,
        }

        local results, err = strategy:delete_consumer_stats(consumers, cutoff_times)
        assert.is_nil(err)
        assert.is_true(results > 0)

        -- delete only really does something in cassandra 3+
        if dao.db.major_version_n >= 3 then
          local res, err = cluster:execute("select * from vitals_consumers")
          assert.is_nil(err)
          assert.same(3, #res)
        end
      end)
    end)


    describe(":insert_status_code_classes()", function()
      it("inserts counts of status code classes", function()
        assert(strategy:init(uuid, hostname))

        local now = ngx.time()
        local now_ms = now * 1000
        local minute = now - (now % 60)
        local minute_ms = minute * 1000

        local data = {
          { 1, now, 1, 1 },
          { 2, now, 1, 3 },
          { 2, now + 1, 1, 5 },
          { 2, minute, 60, 8 },
        }

        assert(strategy:insert_status_code_classes(data))

        local expected = {
          {
            code_class = 1,
            duration    = 1,
            count       = 1,
            at          = now_ms,
          },
          {
            code_class = 2,
            duration    = 1,
            count       = 3,
            at          = now_ms,
          },
          {
            code_class = 2,
            duration    = 1,
            count       = 5,
            at          = now_ms + 1000,
          },
          {
            code_class = 2,
            duration    = 60,
            count       = 8,
            at          = minute_ms,
          },
          meta = {
            has_more_pages = false
          },
          type = "ROWS"
        }

        local res, _ = cluster:execute("select * from vitals_code_classes_by_cluster")

        table.sort(res, function(a,b)
          return a.count < b.count
        end)

        assert.same(expected, res)
      end)
    end)


    describe(":select_status_code_classes()", function()
      -- data starts a couple minutes ago
      local start_at = time() - 90
      local start_minute = start_at - (start_at % 60)

      before_each(function()
        local class_4xx_data = {
          {4, start_at,      1, 1},
          {4, start_at + 1,  1, 3},
          {4, start_minute, 60, 4},
          {4, start_at + 60, 1, 7},
          {4, start_minute + 60, 60, 7},
        }

        local class_5xx_data = {
          {5, start_at + 2,  1, 2},
          {5, start_minute, 60, 2},
          {5, start_at + 60, 1, 5},
          {5, start_at + 61, 1, 6},
          {5, start_at + 62, 1, 8},
          {5, start_minute + 60, 60, 19},
        }

        assert(strategy:insert_status_code_classes(class_4xx_data))
        assert(strategy:insert_status_code_classes(class_5xx_data))
      end)

      after_each(function()
        cluster:execute("TRUNCATE vitals_code_classes_by_cluster")
      end)

      it("returns seconds counts across the cluster", function()
        local opts = {
          duration = 1,
          level = "cluster",
        }

        local results, _ = strategy:select_status_code_classes(opts)

        local expected = {
          {
            node_id     = "cluster",
            code_class  = 4,
            at          = start_at,
            count       = 1,
          },
          {
            node_id     = "cluster",
            code_class  = 5,
            at          = start_at + 2,
            count       = 2,
          },
          {
            node_id     = "cluster",
            code_class  = 4,
            at          = start_at + 1,
            count       = 3,
          },
          {
            node_id     = "cluster",
            code_class  = 5,
            at          = start_at + 60,
            count       = 5,
          },
          {
            node_id     = "cluster",
            code_class  = 5,
            at          = start_at + 61,
            count       = 6,
          },
          {
            node_id     = "cluster",
            code_class  = 4,
            at          = start_at + 60,
            count       = 7,
          },
          {
            node_id     = "cluster",
            code_class  = 5,
            at          = start_at + 62,
            count       = 8,
          },
        }

        table.sort(results, function(a,b)
          return a.count < b.count
        end)

        assert.same(expected, results)
      end)


      it("returns minutes counts across the cluster", function()
        local opts = {
          duration    = 60,
          level       = "cluster",
        }

        local results, _ = strategy:select_status_code_classes(opts)

        local expected = {
          {
            node_id     = "cluster",
            code_class  = 5,
            at          = start_minute,
            count       = 2,
          },
          {
            node_id     = "cluster",
            code_class  = 4,
            at          = start_minute,
            count       = 4,
          },
          {
            node_id     = "cluster",
            code_class  = 4,
            at          = start_minute + 60,
            count       = 7,
          },
          {
            node_id     = "cluster",
            code_class  = 5,
            at          = start_minute + 60,
            count       = 19,
          },
        }

        table.sort(results, function(a,b)
          return a.count < b.count
        end)

        assert.same(expected, results)
      end)
    end)

    describe(":delete_status_code_classes()", function()
      before_each(function()
        cluster:execute("TRUNCATE vitals_code_classes_by_cluster")
        local q = "UPDATE vitals_code_classes_by_cluster SET count=count+? WHERE code_class=? AND at=? AND duration=?"

        local test_data = {
          {cassandra.counter(1), 2, cassandra.timestamp(1510560000000), 1},
          {cassandra.counter(3), 2, cassandra.timestamp(1510560001000), 1},
          {cassandra.counter(4), 2, cassandra.timestamp(1510560002000), 1},
          {cassandra.counter(19), 2, cassandra.timestamp(1510560000000), 60},
          {cassandra.counter(5), 4, cassandra.timestamp(1510560001000), 1},
          {cassandra.counter(7), 4, cassandra.timestamp(1510560002000), 1},
          {cassandra.counter(20), 4, cassandra.timestamp(1510560000000), 60},
          {cassandra.counter(24), 5, cassandra.timestamp(1510560060000), 60},
        }

        for _, row in ipairs(test_data) do
          assert(cluster:execute(q, row, { prepared = true, counter  = true }))
        end

        local res, _ = cluster:execute("select * from vitals_code_classes_by_cluster")
        assert.same(8, #res)
      end)

      after_each(function()
        cluster:execute("TRUNCATE vitals_code_classes_by_cluster")
      end)

      it("cleans up counters", function()
        -- query is "<" so bump the cutoff by a second
        local cutoff_times = {
          minutes = 1510560001,
          seconds = 1510560002,
        }

        local results, err = strategy:delete_status_code_classes(cutoff_times)
        assert.is_nil(err)
        assert.is_true(results > 0)

        -- delete only really does something in cassandra 3+
        if dao.db.major_version_n >= 3 then
          local res, err = cluster:execute("select * from vitals_code_classes_by_cluster")
          assert.is_nil(err)

          assert.same(3, #res)
        end
      end)
    end)

    describe(":insert_status_codes_by_service()", function()
      before_each(function()
        cluster:execute("TRUNCATE vitals_codes_by_service")
      end)

      after_each(function()
        cluster:execute("TRUNCATE vitals_codes_by_service")
      end)

      it("turns Lua tables into Cassandra rows", function()
        local uuid = utils.uuid()

        local now    = ngx.time()
        local minute = now - (now % 60)

        local data = {
          { uuid, "404", tostring(now), "1", 4 },
          { uuid, "404", tostring(now - 1), "1", 2 },
          { uuid, "500", tostring(minute), "60", 5 },
        }

        assert(strategy:insert_status_codes_by_service(data))

        local expected = {
          {
            at         = (now - 1) * 1000,
            code       = 404,
            count      = 2,
            duration   = 1,
            service_id = uuid,
          },
          {
            at         = now * 1000,
            code       = 404,
            count      = 4,
            duration   = 1,
            service_id = uuid,
          },
          {
            at         = minute * 1000,
            code       = 500,
            count      = 5,
            duration   = 60,
            service_id = uuid,
          },
          meta = {
            has_more_pages = false,
          },
          type = 'ROWS',
        }
        local res, _ = cluster:execute("select * from vitals_codes_by_service")

        table.sort(res, function(a,b)
          return a.count < b.count
        end)

        assert.same(expected, res)
      end)

      it("deletes old rows when opts.prune evaluates to true", function()
        local service_id = utils.uuid()
        local data = {
          { service_id, "404", tostring(ngx.time()), "1", 4 },
        }

        local s = spy.on(cassandra_strategy, "delete_status_codes")

        strategy:insert_status_codes(data, {
          entity_type = "service",
          prune = true,
        })

        assert.spy(s).was_called()
      end)

      it("does not delete old rows when opts.prune evaluates to false", function()
        local service_id = utils.uuid()
        local data = {
          { service_id, "404", tostring(ngx.time()), "1", 4 },
        }

        local s = spy.on(cassandra_strategy, "delete_status_codes")

        strategy:insert_status_codes(data, {
          entity_type = "service",
          prune = false,
        })

        assert.spy(s).was_not_called()
      end)

      pending("validates opts", function()
        local data = { data = "anything" }
        local opts = { entity_type = "foo" }
        local _, err = strategy.insert_status_codes(data, opts)

        assert.is_nil(_)
        assert.same("entity_type must be 'service' or 'route'", err)
      end)
    end)

    describe(":select_status_codes_by_service()", function()
      local service_ids = { utils.uuid(), utils.uuid() }
      local now = ngx.time()
      local minute = now - (now % 60)

      before_each(function()
        cluster:execute("TRUNCATE vitals_codes_by_service")
        local q = "UPDATE vitals_codes_by_service SET count=count+? WHERE service_id=? AND code=? AND at=? AND duration=?"

        local test_data = {
          {cassandra.counter(1), cassandra.uuid(service_ids[1]), 200, cassandra.timestamp(now * 1000), 1},
          {cassandra.counter(3), cassandra.uuid(service_ids[1]), 200, cassandra.timestamp((now + 1) * 1000), 1},
          {cassandra.counter(4), cassandra.uuid(service_ids[1]), 200, cassandra.timestamp((now + 2) * 1000), 1},
          {cassandra.counter(19), cassandra.uuid(service_ids[1]), 200, cassandra.timestamp(minute * 1000), 60},
          {cassandra.counter(5), cassandra.uuid(service_ids[2]), 403, cassandra.timestamp((now + 1) * 1000), 1},
          {cassandra.counter(7), cassandra.uuid(service_ids[2]), 404, cassandra.timestamp((now + 2) * 1000), 1},
          {cassandra.counter(20), cassandra.uuid(service_ids[2]), 404, cassandra.timestamp(minute * 1000), 60},
          {cassandra.counter(24), cassandra.uuid(service_ids[2]), 500, cassandra.timestamp((minute + 60) * 1000), 60},
        }

        for _, row in ipairs(test_data) do
          assert(cluster:execute(q, row, { prepared = true, counter  = true }))
        end

        local res, _ = cluster:execute("select * from vitals_codes_by_service")
        assert.same(8, #res)
      end)

      after_each(function()
        cluster:execute("TRUNCATE vitals_codes_by_service")
      end)

      it("retrieves rows", function()
        local opts = {
          ["service_id"] = service_ids[1],
          ["duration"] = 1,
        }
        local res, err = strategy:select_status_codes_by_service(opts)
        assert.is_nil(err)

        table.sort(res, function(a,b)
          return a.count < b.count
        end)

        local expected = {
          {
            at = now,
            code = 200,
            count = 1,
            node_id = 'cluster',
            service_id = service_ids[1],
          },
          {
            at = now + 1,
            code = 200,
            count = 3,
            node_id = 'cluster',
            service_id = service_ids[1],
          },
          {
            at = now + 2,
            code = 200,
            count = 4,
            node_id = 'cluster',
            service_id = service_ids[1],
          }
        }
        assert.same(expected, res)
      end)
    end)

    describe(":delete_status_codes_by_service()", function()
      local service_ids = { utils.uuid(), utils.uuid() }

      before_each(function()
        cluster:execute("TRUNCATE vitals_codes_by_service")
        local q = "UPDATE vitals_codes_by_service SET count=count+? WHERE service_id=? AND code=? AND at=? AND duration=?"

        -- the rows commented with "-- x" we expect will be deleted based on
        -- the `cutoff_times` table below
        local test_data = {
          {cassandra.counter(1), cassandra.uuid(service_ids[1]), 200, cassandra.timestamp(1510560000000), 1}, -- x
          {cassandra.counter(3), cassandra.uuid(service_ids[1]), 200, cassandra.timestamp(1510560001000), 1}, -- x
          {cassandra.counter(4), cassandra.uuid(service_ids[1]), 200, cassandra.timestamp(1510560002000), 1},
          {cassandra.counter(19), cassandra.uuid(service_ids[1]), 200, cassandra.timestamp(1510560000000), 60}, -- x
          {cassandra.counter(5), cassandra.uuid(service_ids[2]), 403, cassandra.timestamp(1510560001000), 1}, -- x
          {cassandra.counter(7), cassandra.uuid(service_ids[2]), 404, cassandra.timestamp(1510560002000), 1},
          {cassandra.counter(20), cassandra.uuid(service_ids[2]), 404, cassandra.timestamp(1510560000000), 60}, -- x
          {cassandra.counter(24), cassandra.uuid(service_ids[2]), 500, cassandra.timestamp(1510560060000), 60},
        }

        for _, row in ipairs(test_data) do
          assert(cluster:execute(q, row, { prepared = true, counter  = true }))
        end

        local res, _ = cluster:execute("select * from vitals_codes_by_service")
        assert.same(8, #res)
      end)

      after_each(function()
        cluster:execute("TRUNCATE vitals_codes_by_service")
      end)

      it("cleans up status_codes_by_service", function()
        -- query is "<" so bump the cutoff by a second
        local cutoff_times = {
          minutes = 1510560001,
          seconds = 1510560002,
        }

        local service_id_map = {}
        for _, v in ipairs(service_ids) do
          service_id_map[v] = true
        end

        local results, err = strategy:delete_status_codes_by_service(service_id_map, cutoff_times)
        assert.is_nil(err)
        assert.is_true(results > 0)

        -- delete only really does something in cassandra 3+
        if dao.db.major_version_n >= 3 then
          local res, err = cluster:execute("select * from vitals_codes_by_service")
          assert.is_nil(err)

          assert.same(3, #res)
        end
      end)
    end)

    describe(":insert_status_codes_by_route()", function()
      before_each(function()
        cluster:execute("TRUNCATE vitals_codes_by_route")
      end)

      it("turns Lua tables into Cassandra rows", function()
        stub(cassandra_strategy, "insert_status_codes")

        local data = {}

        local opts = {
          entity_type = "route",
          prune = true,
        }

        strategy:insert_status_codes_by_route(data)
        assert.stub(cassandra_strategy.insert_status_codes).was_called_with(strategy, data, opts)
      end)
    end)

    describe(":select_status_codes_by_route()", function()
      local route_id_1 = utils.uuid()
      local route_id_2 = utils.uuid()
      local now = ngx.time()
      local minute = now - (now % 60)

      before_each(function()
        cluster:execute("TRUNCATE vitals_codes_by_route")
        local q = [[
          UPDATE vitals_codes_by_route
            SET count=count + ?
            WHERE route_id = ?
            AND code = ?
            AND at = ?
            AND duration = ?
        ]]

        local test_data = {
          {cassandra.counter(5), cassandra.uuid(route_id_1), 400, cassandra.timestamp((now - 3) * 1000), 1},
          {cassandra.counter(25), cassandra.uuid(route_id_1), 301, cassandra.timestamp(minute * 1000), 60},
          {cassandra.counter(57), cassandra.uuid(route_id_1), 404, cassandra.timestamp((minute + 120) * 1000), 60},
          {cassandra.counter(8), cassandra.uuid(route_id_2), 500, cassandra.timestamp((now - 3) * 1000), 1},
          {cassandra.counter(31), cassandra.uuid(route_id_2), 201, cassandra.timestamp(minute * 1000), 60},
          {cassandra.counter(44), cassandra.uuid(route_id_2), 429, cassandra.timestamp((minute + 60) * 1000), 60},
        }

        for _, row in ipairs(test_data) do
          assert(cluster:execute(q, row, { prepared = true, counter  = true }))
        end

        local res, _ = cluster:execute("select * from vitals_codes_by_route")
        assert.same(6, #res)
      end)

      after_each(function()
        cluster:execute("TRUNCATE vitals_codes_by_route")
      end)

      it("retrieves rows", function()
        local opts = {
          ["route_id"] = route_id_1,
          ["duration"] = 60,
        }
        local res, err = strategy:select_status_codes_by_route(opts)
        assert.is_nil(err)

        table.sort(res, function(a,b)
          return a.count < b.count
        end)

        local expected = {
          {
            at = minute,
            code = 301,
            count = 25,
            node_id = "cluster",
            route_id = route_id_1,
          },
          {
            at = minute + 120,
            code = 404,
            count = 57,
            node_id = "cluster",
            route_id = route_id_1,
          }
        }
        assert.same(expected, res)
      end)
    end)

    describe(":delete_status_codes_by_route()", function()
      local route_ids = { utils.uuid(), utils.uuid() }

      before_each(function()
        cluster:execute("TRUNCATE vitals_codes_by_route")
        local q = "UPDATE vitals_codes_by_route SET count=count+? WHERE route_id=? AND code=? AND at=? AND duration=?"

        -- the rows commented with "-- x" we expect will be deleted based on
        -- the `cutoff_times` table below
        local test_data = {
          {cassandra.counter(1), cassandra.uuid(route_ids[1]), 200, cassandra.timestamp(1510560000000), 1}, -- x
          {cassandra.counter(3), cassandra.uuid(route_ids[1]), 200, cassandra.timestamp(1510560001000), 1}, -- x
          {cassandra.counter(4), cassandra.uuid(route_ids[1]), 200, cassandra.timestamp(1510560002000), 1},
          {cassandra.counter(19), cassandra.uuid(route_ids[1]), 200, cassandra.timestamp(1510560000000), 60}, -- x
          {cassandra.counter(5), cassandra.uuid(route_ids[2]), 403, cassandra.timestamp(1510560001000), 1}, -- x
          {cassandra.counter(7), cassandra.uuid(route_ids[2]), 404, cassandra.timestamp(1510560002000), 1},
          {cassandra.counter(20), cassandra.uuid(route_ids[2]), 404, cassandra.timestamp(1510560000000), 60}, -- x
          {cassandra.counter(24), cassandra.uuid(route_ids[2]), 500, cassandra.timestamp(1510560060000), 60},
        }

        for _, row in ipairs(test_data) do
          assert(cluster:execute(q, row, { prepared = true, counter  = true }))
        end

        local res, _ = cluster:execute("select * from vitals_codes_by_route")
        assert.same(8, #res)
      end)

      after_each(function()
        cluster:execute("TRUNCATE vitals_codes_by_route")
      end)

      it("cleans up status_codes_by_route", function()
        -- query is "<" so bump the cutoff by a second
        local cutoff_times = {
          minutes = 1510560001,
          seconds = 1510560002,
        }

        local route_id_map = {}
        for _, v in ipairs(route_ids) do
          route_id_map[v] = true
        end

        local results, err = strategy:delete_status_codes_by_route(route_id_map, cutoff_times)
        assert.is_nil(err)
        assert.is_true(results > 0)

        -- delete only really does something in cassandra 3+
        if dao.db.major_version_n >= 3 then
          local res, err = cluster:execute("select * from vitals_codes_by_route")
          assert.is_nil(err)

          assert.same(3, #res)
        end
      end)
    end)

    describe(":delete_status_codes()", function()
      local service_ids = { utils.uuid(), utils.uuid() }

      before_each(function()
        cluster:execute("TRUNCATE vitals_codes_by_service")
      end)

      after_each(function()
        cluster:execute("TRUNCATE vitals_codes_by_service")
      end)

      it("cleans up status codes by service", function()
        local q = "UPDATE vitals_codes_by_service SET count=count+? WHERE service_id=? AND code=? AND at=? AND duration=?"

        -- the rows commented with "-- x" we expect will be deleted based on
        -- the `opts.seconds_before` and `opts.minutes_before` values below
        local test_data = {
          {cassandra.counter(1), cassandra.uuid(service_ids[1]), 200, cassandra.timestamp(1510560000000), 1}, -- x
          {cassandra.counter(3), cassandra.uuid(service_ids[1]), 200, cassandra.timestamp(1510560001000), 1}, -- x
          {cassandra.counter(4), cassandra.uuid(service_ids[1]), 200, cassandra.timestamp(1510560002000), 1},
          {cassandra.counter(19), cassandra.uuid(service_ids[1]), 200, cassandra.timestamp(1510560000000), 60}, -- x
          {cassandra.counter(5), cassandra.uuid(service_ids[2]), 403, cassandra.timestamp(1510560001000), 1}, -- x
          {cassandra.counter(7), cassandra.uuid(service_ids[2]), 404, cassandra.timestamp(1510560002000), 1},
          {cassandra.counter(20), cassandra.uuid(service_ids[2]), 404, cassandra.timestamp(1510560000000), 60}, -- x
          {cassandra.counter(24), cassandra.uuid(service_ids[2]), 500, cassandra.timestamp(1510560060000), 60},
        }

        for _, row in ipairs(test_data) do
          assert(cluster:execute(q, row, { prepared = true, counter  = true }))
        end

        local res, _ = cluster:execute("SELECT * FROM vitals_codes_by_service")
        assert.same(8, #res)

        local service_id_map = {}
        for _, v in ipairs(service_ids) do
          service_id_map[v] = true
        end

        local opts = {
          entity_type    = "service",
          entities       = service_id_map,
          seconds_before = 1510560002,
          minutes_before = 1510560001,
        }

        local results, err = strategy:delete_status_codes(opts)
        assert.is_nil(err)
        assert.is_true(results > 0)

        -- delete only really does something in cassandra 3+
        if dao.db.major_version_n >= 3 then
          local res, err = cluster:execute("select * from vitals_codes_by_service")
          assert.is_nil(err)

          assert.same(3, #res)
        end
      end)

      it("does not clean up status codes for an invalid entity type", function()
        if dao.db.major_version_n < 3 then
          pending("fails on Cassandra 2.2", function() end)
          return
        end

        local service_id_map = {}
        for _, v in ipairs(service_ids) do
          service_id_map[v] = true
        end

        local opts = {
          entity_type    = nil,
          entities       = service_id_map,
          seconds_before = 1510560002,
          minutes_before = 1510560001,
        }

        local _, err = strategy:delete_status_codes(opts)

        assert.is_nil(_)
        assert.same(err, "entity_type must be service or route")
      end)
    end)

    describe(":node_exists()", function()
      it("should return false if the node does not exist", function()
        local node_1 = utils.uuid()

        assert.same(strategy:node_exists(node_1), false)
      end)

      it("should return true if the node exists", function()
        local node_2 = utils.uuid()

        local q = "insert into vitals_node_meta(node_id) values(" .. node_2 .. ")"
        assert(cluster:execute(q))

        assert.same(strategy:node_exists(node_2), true)
      end)

      it("should return nil if the node_id is invalid", function()
        local node_3 = "123"

        assert.same(strategy:node_exists(node_3), nil)
      end)
    end)

    describe(":select_node_meta()", function()
      local node_id  = utils.uuid()
      local hostname = "testhostname"

      local node_id_2  = utils.uuid()
      local hostname_2 = "testhostname-2"

      after_each(function()
        assert(dao.db:query("truncate table vitals_node_meta"))
      end)

      it("retrieves node_id and hostname for a list of nodes", function()

        local data_to_insert = {
          { node_id, hostname },
          { node_id_2, hostname_2 },
        }

        local q = "insert into vitals_node_meta(node_id, hostname) values( %s, '%s')"

        for _, row in ipairs(data_to_insert) do
          local query = fmt(q, unpack(row))
          assert(cluster:execute(query))
        end

        local expected = {
          {
            hostname = hostname,
            node_id = node_id
          },
          {
            hostname = hostname_2,
            node_id = node_id_2
          }
        }

        local res, _ = strategy:select_node_meta({ node_id, node_id_2 })

        -- sort for predictable results
        table.sort(res, function(a,b)
          return a.hostname < b.hostname
        end)

        assert.same(expected, res)
      end)

      it("returns an empty table when no nodes are passed in", function()
        local res, _ = strategy:select_node_meta({})

        assert.same({}, res)

        res, _ = strategy:select_node_meta()

        assert.same({}, res)
      end)
    end)
  end)
end)
