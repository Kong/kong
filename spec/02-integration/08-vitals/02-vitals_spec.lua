local dao_factory  = require "kong.dao.factory"
local kong_vitals  = require "kong.vitals"
local singletons   = require "kong.singletons"
local dao_helpers  = require "spec.02-integration.03-dao.helpers"
local utils        = require "kong.tools.utils"
local json_null  = require("cjson").null
local cassandra = require "cassandra"

local ngx_time     = ngx.time
local fmt          = string.format


dao_helpers.for_each_dao(function(kong_conf)
  describe("vitals with db: " .. kong_conf.database, function()
    local vitals
    local dao
    local snapshot

    local stat_labels = {
      "cache_datastore_hits_total",
      "cache_datastore_misses_total",
      "latency_proxy_request_min_ms",
      "latency_proxy_request_max_ms",
      "latency_upstream_min_ms",
      "latency_upstream_max_ms",
      "requests_proxy_total",
      "latency_proxy_request_avg_ms",
      "latency_upstream_avg_ms",
    }

    local consumer_stat_labels = {
      "requests_consumer_total",
    }

    setup(function()
      dao = assert(dao_factory.new(kong_conf))
      assert(dao:run_migrations())

      vitals = kong_vitals.new({
        dao = dao,
      })

      singletons.configuration = { vitals = true }
      vitals:init()
    end)

    before_each(function()
      snapshot = assert:snapshot()
    end)

    after_each(function()
      snapshot:revert()
    end)

    describe("phone_home()", function()
      before_each(function()
        assert(dao.db:truncate_table("vitals_stats_minutes"))
        assert(dao.db:truncate_table("vitals_node_meta"))
        assert(vitals.list_cache:delete("vitals:ph_stats"))
      end)

      it("returns phone home data", function()
          -- data starts 10 minutes ago
          local minute_start_at = ngx_time() - ( ngx_time() % 60 ) - 600
          local data = {
            { minute_start_at, 0, 0, nil, nil, nil, nil, 0, 10, 100, 19, 200 },
            { minute_start_at + 1, 19, 99, 0, 120, 12, 47, 7, 6, 50, 13, 150 },
          }
          assert(vitals.strategy:insert_stats(data))

          assert.same(19, vitals:phone_home("v.cdht"))
          assert.same(99, vitals:phone_home("v.cdmt"))
          assert.same(120, vitals:phone_home("v.lprx"))
          assert.same(0, vitals:phone_home("v.lprn"))
          assert.same(47, vitals:phone_home("v.lux"))
          assert.same(12, vitals:phone_home("v.lun"))

          -- test data is set up to test rounding down: 150 / 16 = 9.375
          assert.same(9, vitals:phone_home("v.lpra"))

          -- test data is set up to test rounding up: 350 / 32 = 10.9375
          assert.same(11, vitals:phone_home("v.lua"))
      end)

      it("returns nil when there is no data", function()
        assert.is_nil(vitals:phone_home("v.cdht"))
        assert.is_nil(vitals:phone_home("v.cdmt"))
        assert.is_nil(vitals:phone_home("v.lprx"))
        assert.is_nil(vitals:phone_home("v.lprn"))
        assert.is_nil(vitals:phone_home("v.lux"))
        assert.is_nil(vitals:phone_home("v.lun"))
        assert.is_nil(vitals:phone_home("v.lpra"))
        assert.is_nil(vitals:phone_home("v.lua"))
      end)

      it("doesn't include sentinel values", function()
        -- data starts 10 minutes ago
        local minute_start_at = ngx_time() - ( ngx_time() % 60 ) - 600
        local data = {
          { minute_start_at, 0, 0, nil, nil, nil, nil, 0, 0, 0, 0, 0 },
          { minute_start_at + 1, 19, 99, nil, nil, nil, nil, 7, 0, 0, 0, 0 },
        }
        assert(vitals.strategy:insert_stats(data))

        assert.same(19, vitals:phone_home("v.cdht"))
        assert.same(99, vitals:phone_home("v.cdmt"))
        assert.is_nil(vitals:phone_home("v.lprx"))
        assert.is_nil(vitals:phone_home("v.lprn"))
        assert.is_nil(vitals:phone_home("v.lux"))
        assert.is_nil(vitals:phone_home("v.lun"))
      end)
    end)

    describe("flush_lock()", function()
      before_each(function()
        ngx.shared.kong_vitals_lists:delete("vitals:flush_lock")
      end)

      teardown(function()
        ngx.shared.kong_vitals_lists:delete("vitals:flush_lock")

        local v = ngx.shared.kong_vitals_lists:get("vitals:flush_lock")
        assert.is_nil(v)
      end)

      it("returns true upon acquiring a lock", function()
        local vitals = kong_vitals.new { dao = dao }

        local ok, err = vitals:flush_lock()
        assert.is_true(ok)
        assert.is_nil(err)
      end)

      it("returns false when failing to acquire a lock, without err", function()
        local vitals = kong_vitals.new { dao = dao }

        local ok, err = vitals:flush_lock()
        assert.is_true(ok)
        assert.is_nil(err)

        local vitals2 = kong_vitals.new { dao = dao }

        ok, err = vitals2:flush_lock()
        assert.is_false(ok)
        assert.is_nil(err)
      end)
    end)

    -- pending until we can mock out list shm functions
    pending("poll_worker_data()", function()
      local flush_key = "vitals:flush_list:" .. ngx.time()
      local expected  = 3

      setup(function()
        ngx.shared.kong:delete(flush_key)

        for i = 1, expected do
          ngx.shared.kong:rpush(flush_key, "foo")
        end
      end)

      it("returns true when all workers have posted data", function()
        local vitals = kong_vitals.new { dao = dao }

        local ok, err = vitals:poll_worker_data(flush_key, expected)
        assert.is_true(ok)
        assert.is_nil(err)
      end)

      it("returns false when it times out", function()
        setup(function()
          ngx.shared.kong:lpop(flush_key)
        end)

        local vitals = kong_vitals.new { dao = dao }

        local ok, err = vitals:poll_worker_data(flush_key, expected)
        assert.is_false(ok)
        assert.same("timeout waiting for workers to post vitals data", err)
      end)
    end)

    describe(".table_names()", function()
      before_each(function()
        if dao.db_type == "postgres" then
          -- this is ugly, but tests are creating dynamic tables and
          -- not cleaning them up. will sort that in another PR
          dao:drop_schema()
          dao:run_migrations()

          -- insert a fake stats table
          assert(dao.db:query("create table if not exists vitals_stats_seconds_foo (like vitals_stats_seconds)"))
        end
      end)

      after_each(function()
        if dao.db_type == "postgres" then
          assert(dao.db:query("drop table if exists vitals_stats_seconds_foo"))
        end
      end)

      it("returns all vitals table names", function()
        local results, _ = kong_vitals.table_names(dao)

        local expected = {
          "vitals_code_classes_by_cluster",
          "vitals_consumers",
          "vitals_node_meta",
          "vitals_stats_hours",
          "vitals_stats_minutes",
          "vitals_stats_seconds",
        }

        if (dao.db_type == "postgres") then
          expected[7] = "vitals_stats_seconds_foo"
        end

        assert.same(expected, results)
      end)
    end)

    describe("current_bucket()", function()
      before_each(function()
        vitals:reset_counters()
      end)

      it("returns the current bucket", function()
        local res, err = vitals:current_bucket()

        assert.is_nil(err)
        assert.same(0, res)
      end)

      it("only returns good bucket indexes (lower-bound check)", function()
        vitals.counters.start_at = ngx_time() + 1

        local res, err = vitals:current_bucket()

        assert.same("bucket -1 out of range for counters starting at " .. vitals.counters.start_at, err)
        assert.is_nil(res)
      end)

      it("puts later data in the last bucket so we don't lose it", function()
        local vitals = kong_vitals.new({
          dao            = dao,
          flush_interval = 60,
        })

        vitals.counters.start_at = ngx.time() - 60

        local res, err = vitals:current_bucket()

        assert.is_nil(err)
        assert.same(59, res)
      end)
    end)

    describe("cache_accessed()", function()
      it("doesn't increment the cache counter when vitals is off", function()
        singletons.configuration = { vitals = false }

        local vitals = kong_vitals.new { dao = dao }
        vitals:reset_counters()

        assert.same("vitals not enabled", vitals:cache_accessed(2))
      end)

      it("does increment the cache counter when vitals is on", function()
        singletons.configuration = { vitals = true }

        local vitals = kong_vitals.new { dao = dao, flush_interval = 1 }
        stub(vitals, "enabled").returns(true)

        vitals:reset_counters()

        local initial_l2_counter = vitals.counters.metrics[0].l2_hits

        vitals:cache_accessed(2)

        assert.same(initial_l2_counter + 1, vitals.counters.metrics[0].l2_hits)
      end)
    end)

    describe("log_latency()", function()
      it("doesn't log latency when vitals is off", function()
        singletons.configuration = { vitals = false }

        local vitals = kong_vitals.new { dao = dao }
        vitals:reset_counters()

        assert.same("vitals not enabled", vitals:log_latency(7))
      end)

      it("does log latency when vitals is on", function()
        singletons.configuration = { vitals = true }

        local vitals = kong_vitals.new { dao = dao }
        stub(vitals, "enabled").returns(true)

        vitals:reset_counters()

        vitals:log_latency(7)
        vitals:log_latency(91)

        assert.same(7, vitals.counters.metrics[0].proxy_latency_min)
        assert.same(91, vitals.counters.metrics[0].proxy_latency_max)
        assert.same(2, vitals.counters.metrics[0].proxy_latency_count)
        assert.same(98, vitals.counters.metrics[0].proxy_latency_total)
      end)
    end)

    describe("log_upstream_latency()", function()
      it("doesn't log upstream latency when vitals is off", function()
        singletons.configuration = { vitals = false }

        local vitals = kong_vitals.new { dao = dao }
        vitals:reset_counters()

        assert.same("vitals not enabled", vitals:log_upstream_latency(7))
      end)

      it("does log upstream latency when vitals is on", function()
        singletons.configuration = { vitals = true }

        local vitals = kong_vitals.new { dao = dao }
        stub(vitals, "enabled").returns(true)

        vitals:reset_counters()

        vitals:log_upstream_latency(20)
        vitals:log_upstream_latency(80)
        vitals:log_upstream_latency(11)

        assert.same(11, vitals.counters.metrics[0].ulat_min)
        assert.same(80, vitals.counters.metrics[0].ulat_max)
        assert.same(3, vitals.counters.metrics[0].ulat_count)
        assert.same(111, vitals.counters.metrics[0].ulat_total)
      end)
    end)

    describe("log_request()", function()
      it("doesn't log when vitals is off", function()
        local vitals = kong_vitals.new { dao = dao }
        stub(vitals, "enabled").returns(false)

        assert.same("vitals not enabled", vitals:log_request(nil))
      end)

      it("does log when vitals is on", function()
        local vitals = kong_vitals.new { dao = dao }
        stub(vitals, "enabled").returns(true)

        vitals:reset_counters()

        local ctx = { authenticated_consumer =  { id = utils.uuid() }}
        local ok, _ = vitals:log_request(ctx)

        assert.not_nil(ok)
      end)
    end)

    describe("log_status_code()", function()
      it("doesn't log when vitals is off", function()
        local vitals = kong_vitals.new { dao = dao }
        stub(vitals, "enabled").returns(false)

        assert.same("vitals not enabled", vitals:log_status_code(nil))
      end)

      it("doesnt log when passed a non-integer status code", function()
        local vitals = kong_vitals.new { dao = dao }
        stub(vitals, "enabled").returns(true)

        vitals:reset_counters()

        assert.same("integer status code is required", vitals:log_status_code("nope"))
        assert.same("integer status code is required", vitals:log_status_code(nil))
      end)

      it("does log when vitals is on", function()
        local vitals = kong_vitals.new { dao = dao }
        stub(vitals, "enabled").returns(true)

        vitals:reset_counters()

        local status = 200
        local ok, _ = vitals:log_status_code(status)

        assert.equal(status, ok)
      end)
    end)

    describe("flush_status_code_counters()", function()
      it("returns the number of counters flushed", function()
        stub(vitals, "enabled").returns(true)

        vitals:reset_counters()
        vitals:log_status_code(200)

        assert.equal(2, vitals:flush_status_code_counters())
      end)
    end)

    describe("log_phase_after_plugins()", function()
      -- our mock shm doesn't mock flush_all and flush_expired,
      -- so we have to clean it up key-by-key (?)
      local now
      local seconds_key
      local minutes_key

      before_each(function()
        now = ngx_time()
        seconds_key = now .. "|1|myservice|myroute|200|"
        minutes_key = (now - (now % 60)) .. "|60|myservice|myroute|200|"
      end)

      after_each(function()
        vitals.dict:delete(seconds_key)
        vitals.dict:delete(minutes_key)
      end)

      it("caches info about the request", function()
        local status = "200"
        local ctx = {
          ["service"] = {
            ["id"] = "myservice",
          },
          ["route"] = {
            ["id"] = "myroute",
          },
        }

        vitals:log_phase_after_plugins(ctx, status)

        local seconds = vitals.dict:get(seconds_key)
        local minutes = vitals.dict:get(minutes_key)

        assert.same(1, seconds)
        assert.same(1, minutes)
      end)
    end)

    describe("flush_vitals_cache()", function()
      if dao.db.name == "postgres" then
        pending("pending implementation of vitals_codes_by_route", function() end)
        return
      end

      before_each(function()
        assert(dao.db:truncate_table("vitals_codes_by_route"))
        assert(dao.db:truncate_table("vitals_codes_by_service"))
      end)

      after_each(function()
        vitals.dict:flush_all() -- mark expired
        vitals.dict:flush_expired() -- really clean them up
        assert(dao.db:truncate_table("vitals_codes_by_route"))
        assert(dao.db:truncate_table("vitals_codes_by_service"))
      end)

      it("flushes cache entries", function()
        stub(vitals, "enabled").returns(true)

        local service_id = utils.uuid()
        local route_id = utils.uuid()
        local now = ngx_time()
        local minute = now - (now % 60)

        local cache_entries = {
          (now - 1) .. "|1|" .. service_id .. "|" .. route_id .. "|200|",
          now .. "|1|" .. service_id .. "|" .. route_id .. "|404|",
          minute .. "|60|" .. service_id .. "|" .. route_id .. "|200|",
          minute .. "|60|" .. service_id .. "|" .. route_id .. "|404|",
        }

        for i, v in ipairs(cache_entries) do
          assert(vitals.dict:set(v, i))
        end
        assert.same(4, #vitals.dict:get_keys())

        local res, err = vitals:flush_vitals_cache()
        assert.is_nil(err)
        assert.same(4, res)

        local res, err = vitals:get_status_codes_by_service({
          service_id = service_id,
          duration = "seconds",
          level = "cluster"
        })

        assert.is_nil(err)

        local expected = {
          [tostring(now - 1)] = {
            ["200"] = 1,
          },
          [tostring(now)] = {
            ["404"] = 2,
          }
        }

        assert.same(expected, res.stats.cluster)

        local res, err = dao.db:query("select * from vitals_codes_by_route")

        assert.is_nil(err)

        table.sort(res, function(a,b)
          return a.count < b.count
        end)

        local ats = {
          now - 1,
          now,
          minute,
          minute,
        }
        if dao.db.name == "cassandra" then
          for i, v in ipairs(ats) do
            ats[i] = v * 1000
          end
        end

        local expected = {
          {
            at = ats[1],
            code = 200,
            count = 1,
            duration = 1,
            route_id = route_id,
          }, {
            at = ats[2],
            code = 404,
            count = 2,
            duration = 1,
            route_id = route_id,
          }, {
            at = ats[3],
            code = 200,
            count = 3,
            duration = 60,
            route_id = route_id,
          }, {
            at = ats[4],
            code = 404,
            count = 4,
            duration = 60,
            route_id = route_id,
          }
        }

        for i = 1, 4 do
          assert.same(expected[i], res[i])
        end
      end)
    end)

    describe("init()", function()
      it("doesn't initialize strategy  when vitals is off", function()
        singletons.configuration = { vitals = false }

        local vitals = kong_vitals.new { dao = dao }
        vitals:reset_counters()

        local s_strategy = spy.on(vitals.strategy, "init")

        vitals:init()

        assert.spy(s_strategy).was_called(0)
      end)
      it("does initialize strategy when vitals is on", function()
        singletons.configuration = { vitals = true }

        local vitals = kong_vitals.new({
          dao = dao,
        })
        vitals:reset_counters()

        local s_strategy = spy.on(vitals.strategy, "init")

        vitals:init()

        assert.spy(s_strategy).was_called(1)
      end)
    end)

    describe("get_consumer_stats()", function()
      local node_1  = "20426633-55dc-4050-89ef-2382c95a611e"
      local node_2  = "8374682f-17fd-42cb-b1dc-7694d6f65ba0"
      local cons_id = utils.uuid()
      local now

      before_each(function()
        -- time series conveniently starts at the top of the minute
        now = ngx_time() - (ngx_time() % 60)


        local data_to_insert = {
          {cons_id, node_1, now, 1, 1},
          {cons_id, node_1, now + 1, 1, 3},
          {cons_id, node_1, now + 2, 1, 4},
          {cons_id, node_1, now, 60, 19},
          {cons_id, node_2, now + 1, 1, 5},
          {cons_id, node_2, now + 2, 1, 7},
          {cons_id, node_2, now, 60, 20},
          {cons_id, node_2, now + 60, 60, 24},
        }

        local nodes = { node_1, node_2 }

        local q, node_q

        if dao.db_type == "postgres" then
          node_q = "insert into vitals_node_meta(node_id, hostname) values('%s', '%s')"
          q = [[
            insert into vitals_consumers(consumer_id, node_id, at, duration, count)
            values('%s', '%s', to_timestamp(%d), %d, %d)
          ]]

          for i, node in ipairs(nodes) do
            assert(dao.db:query(fmt(node_q, node, "testhostname" .. i)))
          end

          for _, row in ipairs(data_to_insert) do
            assert(dao.db:query(fmt(q, unpack(row))))
          end
        else
          node_q = "insert into vitals_node_meta(node_id, hostname) values (?, ?)"
          q = [[
            update vitals_consumers
            set count = count + ?
            where consumer_id = ?
            and node_id = ?
            and at = ?
            and duration = ?
          ]]

          for i, node in ipairs(nodes) do
            local args = {
              cassandra.uuid(node),
              "testhostname" .. i,
            }
            assert(dao.db.cluster:execute(node_q, args, { prepared = true }))
          end

          local counter_options = {
            prepared = true,
            counter  = true,
          }

          for _, row in ipairs(data_to_insert) do
            local cons_id, node_id, at, duration, count = unpack(row)
            assert(dao.db.cluster:execute(q, {
              cassandra.counter(count),
              cassandra.uuid(cons_id),
              cassandra.uuid(node_id),
              cassandra.timestamp(at * 1000),
              duration,
            }, counter_options))
          end
        end
      end)

      after_each(function()
        assert(dao.db:query("truncate table vitals_consumers"))
        assert(dao.db:query("truncate table vitals_node_meta"))
      end)

      it("returns seconds stats for a consumer across the cluster", function()
        local res, _ = vitals:get_consumer_stats({
          consumer_id = cons_id,
          duration    = "seconds",
          level       = "cluster",
        })

        local expected = {
          meta = {
            level = "cluster",
            interval = "seconds",
            earliest_ts = now,
            latest_ts = now + 2,
            stat_labels = consumer_stat_labels,
          },
          stats = {
            cluster = {
              [tostring(now)] = 1,
              [tostring(now + 1)] = 8,
              [tostring(now + 2)] = 11,
            }
          }
        }

        assert.same(expected, res)
      end)

      it("returns seconds stats for a consumer and a node", function()
        local res, _ = vitals:get_consumer_stats({
          consumer_id = cons_id,
          duration    = "seconds",
          level       = "node",
          node_id     = node_1,
        })

        local expected = {
          meta = {
            level = "node",
            interval = "seconds",
            earliest_ts = now,
            latest_ts = now + 2,
            stat_labels = consumer_stat_labels,
            nodes = {
              [node_1] = { hostname = "testhostname1"}
            }
          },
          stats = {
            [node_1] = {
              [tostring(now)] = 1,
              [tostring(now + 1)] = 3,
              [tostring(now + 2)] = 4,
            }
          }
        }

        assert.same(expected, res)
      end)

      it("returns minutes stats for a consumer across the cluster", function()
        local res, _ = vitals:get_consumer_stats({
          consumer_id = cons_id,
          duration    = "minutes",
          level       = "cluster",
        })

        local expected = {
          meta = {
            level = "cluster",
            interval = "minutes",
            earliest_ts = now,
            latest_ts = now + 60,
            stat_labels = consumer_stat_labels,
          },
          stats = {
            cluster = {
              [tostring(now)] = 39,
              [tostring(now + 60)] = 24,
            }
          }
        }

        assert.same(expected, res)
      end)

      it("returns minutes stats for a consumer and a node", function()
        local res, _ = vitals:get_consumer_stats({
          consumer_id = cons_id,
          duration    = "minutes",
          level       = "node",
          node_id     = node_2,
        })

        local expected = {
          meta = {
            level = "node",
            interval = "minutes",
            earliest_ts = now,
            latest_ts = now + 60,
            stat_labels = consumer_stat_labels,
            nodes = {
              [node_2] = { hostname = "testhostname2"}
            }
          },
          stats = {
            [node_2] = {
              [tostring(now)] = 20,
              [tostring(now + 60)] = 24,
            }
          }
        }

        assert.same(expected, res)
      end)
    end)

    describe("get_stats()", function()
      local vitals
      local now = ngx.time()
      local mockStats = {
        {
          node_id = "node_one",
          at = now,
          l2_hit = 100,
          l2_miss = 50,
          plat_min = 5,
          plat_max = 20,
          ulat_min =  nil,
          ulat_max = nil,
          requests = 500,
          plat_total = 100,
          plat_count = 10,
          ulat_total = nil,
          ulat_count = 0,
        },
        {
          node_id = "node_one",
          at = now + 1,
          l2_hit = 75,
          l2_miss = 41,
          plat_min = nil,
          plat_max = nil,
          ulat_min = 0,
          ulat_max = 15,
          requests = 1000,
          plat_total = nil,
          plat_count = 0,
          ulat_total = 200,
          ulat_count = 20,
        }
      }

      setup(function()
        vitals = kong_vitals.new { dao = dao }
        stub(vitals.strategy, "select_stats").returns(mockStats)
        stub(vitals.strategy, "select_node_meta").returns({})
      end)

      it("rejects invalid query_type", function()
        local res, err = vitals:get_stats("foo")

        local expected = "Invalid query params: interval must be 'minutes' or 'seconds'"

        assert.is_nil(res)
        assert.same(expected, err)
      end)

      it("rejects invalid level", function()
        local res, err = vitals:get_stats("minutes", "not_legit")

        local expected = "Invalid query params: level must be 'cluster' or 'node'"

        assert.is_nil(res)
        assert.same(expected, err)
      end)

      it("rejects invalid node_id", function()
        local res, err = vitals:get_stats("minutes", "cluster", "nope")

        local expected = "Invalid query params: invalid node_id"

        assert.is_nil(res)
        assert.same(expected, err)
      end)

      it("returns converted stats", function()
        local expected = {
          meta = {
            earliest_ts = now,
            interval = "seconds",
            latest_ts = now + 1,
            level = "node",
            nodes = {},
            stat_labels = stat_labels
          },
          stats = {
            node_one = {
              [tostring(now)] = { 100, 50, 5, 20, json_null, json_null, 500, 10, json_null },
              [tostring(now + 1)] = { 75, 41, json_null, json_null, 0, 15, 1000, json_null, 10 }
            }
          }
        }
        local res, _ = vitals:get_stats("seconds", "node")
        assert.same(res, expected)
      end)
    end)

    describe("get_status_codes()", function()
      local vitals
      local now = ngx_time()
      local data_to_insert = {
        { at = now - 1, code_class = 4, count = 10 },
        { at = now, code_class = 4, count = 47 },
        { at = now, code_class = 5, count = 12 },
      }

      setup(function()
        vitals = kong_vitals.new { dao = dao }
        stub(vitals.strategy, "select_status_code_classes").returns(data_to_insert)
      end)

      it("rejects invalid query_type", function()
        local res, err = vitals:get_status_codes({
          duration = "foo",
          level    = "cluster",
        })

        local expected = "Invalid query params: interval must be 'minutes' or 'seconds'"

        assert.is_nil(res)
        assert.same(expected, err)
      end)

      it("rejects invalid level", function()
        local res, err = vitals:get_status_codes({
          duration = "minutes",
          level    = "not_legit",
        })

        local expected = "Invalid query params: level must be 'cluster'"

        assert.is_nil(res)
        assert.same(expected, err)
      end)

      it("returns converted stats", function()
        local expected = {
          meta = {
            earliest_ts = now - 1,
            interval = "seconds",
            latest_ts = now,
            level = "cluster",
          },
          stats = {
            cluster = {
              [tostring(now - 1)] = {
                ["4xx"] = 10,
              },
              [tostring(now)] = {
                ["4xx"] = 47,
                ["5xx"] = 12,
              },
            }
          }
        }

        local res, _ = vitals:get_status_codes({
          duration = "seconds",
          level    = "cluster",
        })

        assert.same(res, expected)
      end)
    end)

    describe("get_status_codes_by_service()", function()
      local vitals
      local now = ngx_time()
      local uuid = utils.uuid()

      local data_to_insert = {
        { service_id = uuid, at = now, code = 400, count = 5 },
        { service_id = uuid, at = now, code = 200, count = 533 },
        { service_id = uuid, at = now - 1 , code = 200, count = 6 },
        { service_id = uuid, at = now - 1 , code = 204, count = 17 },
        { service_id = uuid, at = now - 2, code = 500, count = 1 },
      }

      setup(function()
        vitals = kong_vitals.new { dao = dao }
        stub(vitals.strategy, "select_status_codes_by_service").returns(data_to_insert)
      end)

      it("rejects invalid query_type", function()
        local res, err = vitals:get_status_codes_by_service({
          duration = "foo",
          level    = "cluster",
          service_id = uuid,
        })

        local expected = "Invalid query params: interval must be 'minutes' or 'seconds'"

        assert.is_nil(res)
        assert.same(expected, err)
      end)

      it("rejects invalid level", function()
        local res, err = vitals:get_status_codes_by_service({
          duration = "minutes",
          level    = "not_legit",
          service_id = uuid,
        })

        local expected = "Invalid query params: level must be 'cluster'"

        assert.is_nil(res)
        assert.same(expected, err)
      end)

      it("rejects invalid service id", function()
        local res, err = vitals:get_status_codes_by_service({
          duration = "minutes",
          level    = "cluster",
          service_id = "nope",
        })

        local expected = "Invalid query params: invalid service_id"

        assert.is_nil(res)
        assert.same(expected, err)
      end)

      it("returns converted stats", function()

        local expected = {
          meta = {
            entity_type = "service",
            entity_id = uuid,
            earliest_ts = now - 2,
            interval = "seconds",
            latest_ts = now,
            level = "cluster",
          },
          stats = {
            cluster = {
              [tostring(now - 2)] = {
                ["500"] = 1,
              },
              [tostring(now - 1)] = {
                ["200"] = 6,
                ["204"] = 17,
              },
              [tostring(now)] = {
                ["400"] = 5,
                ["200"] = 533
              },
            }
          }
        }

        local res, _ = vitals:get_status_codes_by_service({
          duration = "seconds",
          level    = "cluster",
          service_id = uuid,
        })

        assert.same(res, expected)
      end)
    end)

    describe("get_node_meta()", function()
      after_each(function()
        assert(dao.db:query("truncate table vitals_node_meta"))
      end)

      it("returns metadata for the requested node ids", function()
        local node_id  = utils.uuid()
        local hostname = "testhostname"

        local node_id_2  = utils.uuid()
        local hostname_2 = "testhostname-2"

        local data_to_insert = {
          { node_id, hostname },
          { node_id_2, hostname_2 },
        }

        local q = "insert into vitals_node_meta(node_id, hostname) values('%s', '%s')"

        for _, row in ipairs(data_to_insert) do
          if kong_conf.database == "cassandra" then
            assert(vitals.strategy:init(unpack(row)))
          else
            assert(dao.db:query(fmt(q, unpack(row))))
          end
        end

        local res, _ = vitals:get_node_meta({ node_id, node_id_2 })

        local expected = {
          [node_id] = { hostname = hostname},
          [node_id_2] = { hostname = hostname_2},
        }

        assert.same(expected, res)
      end)

      it("returns an empty table when no nodes are passed in", function()
        local res, _ = vitals:get_node_meta({})

        assert.same({}, res)
      end)
    end)
  end)

end)
