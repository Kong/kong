local kong_vitals  = require "kong.vitals"
local utils        = require "kong.tools.utils"
local json_null  = require("cjson").null
local helpers = require "spec.helpers"

local ngx_time     = ngx.time
local fmt          = string.format


for _, strategy in helpers.each_strategy() do
  describe("vitals with db: #" .. strategy, function()
    local vitals
    local snapshot
    local db

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
      db = select(2, helpers.get_db_utils(strategy))

      kong.configuration = { vitals = true }
      vitals = kong_vitals.new({
        db = db,
      })

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
        assert(db:truncate("vitals_stats_minutes"))
        assert(db:truncate("vitals_node_meta"))
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
        local vitals = kong_vitals.new { db = db }

        local ok, err = vitals:flush_lock()
        assert.is_true(ok)
        assert.is_nil(err)
      end)

      it("returns false when failing to acquire a lock, without err", function()
        local vitals = kong_vitals.new { db = db }

        local ok, err = vitals:flush_lock()
        assert.is_true(ok)
        assert.is_nil(err)

        local vitals2 = kong_vitals.new { db = db }

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
        local vitals = kong_vitals.new { db = db }

        local ok, err = vitals:poll_worker_data(flush_key, expected)
        assert.is_true(ok)
        assert.is_nil(err)
      end)

      it("returns false when it times out", function()
        setup(function()
          ngx.shared.kong:lpop(flush_key)
        end)

        local vitals = kong_vitals.new { db = db }

        local ok, err = vitals:poll_worker_data(flush_key, expected)
        assert.is_false(ok)
        assert.same("timeout waiting for workers to post vitals data", err)
      end)
    end)

    describe(".logging_metrics", function()
      it("returns metadata about metrics stored in ngx.ctx", function()
        local res = kong_vitals.logging_metrics

        local expected = {
          cache_metrics = {
            cache_datastore_hits_total = "counter",
            cache_datastore_misses_total = "counter",
          }
        }
        assert.same(expected, res)
      end)
    end)

    describe(".table_names()", function()
      before_each(function()
        if db.strategy == "postgres" then
          -- this is ugly, but tests are creating dynamic tables and
          -- not cleaning them up. will sort that in another PR
          db:schema_reset()
          helpers.bootstrap_database(db)

          -- insert a fake stats table
          assert(db.connector:query("create table if not exists vitals_stats_seconds_foo (like vitals_stats_seconds)"))
        end
      end)

      after_each(function()
        if db.strategy == "postgres" then
          assert(db.connector:query("drop table if exists vitals_stats_seconds_foo"))
        end
      end)

      it("returns all vitals table names", function()
        local results, _ = kong_vitals.table_names(db)

        local expected = {
          "vitals_code_classes_by_cluster",
          "vitals_code_classes_by_workspace",
          "vitals_codes_by_consumer_route",
          "vitals_codes_by_route",
          "vitals_codes_by_service",
          "vitals_consumers",
          "vitals_locks",
          "vitals_node_meta",
          "vitals_stats_hours",
          "vitals_stats_minutes",
          "vitals_stats_seconds",
        }

        if (db.strategy == "postgres") then
          table.insert(expected, "vitals_stats_seconds_foo")
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
          db = db,
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
        kong.configuration = { vitals = false }

        local vitals = kong_vitals.new { db = db }
        vitals:reset_counters()

        assert.same("vitals not enabled", vitals:cache_accessed(2))
      end)

      it("does increment the cache counter when vitals is on", function()
        kong.configuration = { vitals = true }

        local vitals = kong_vitals.new { db = db, flush_interval = 1 }
        stub(vitals, "enabled").returns(true)

        vitals:reset_counters()

        local initial_l2_counter = vitals.counters.metrics[0].l2_hits

        vitals:cache_accessed(2)

        assert.same(initial_l2_counter + 1, vitals.counters.metrics[0].l2_hits)
      end)

      it("increments counters in ngx.ctx", function()
        ngx.ctx.cache_metrics = nil
        assert.is_nil(ngx.ctx.cache_metrics)

        vitals:cache_accessed(2)

        local expected = {
          cache_datastore_hits_total = 1,
          cache_datastore_misses_total = 0,
        }

        assert.same(expected, ngx.ctx.cache_metrics)

        vitals:cache_accessed(3)
        vitals:cache_accessed(2)

        expected = {
          cache_datastore_hits_total = 2,
          cache_datastore_misses_total = 1,
        }

        assert.same(expected, ngx.ctx.cache_metrics)
      end)
    end)

    describe("log_latency()", function()
      it("doesn't log latency when vitals is off", function()
        kong.configuration = { vitals = false }

        local vitals = kong_vitals.new { db = db }
        vitals:reset_counters()

        assert.same("vitals not enabled", vitals:log_latency(7))
      end)

      it("does log latency when vitals is on", function()
        kong.configuration = { vitals = true }

        local vitals = kong_vitals.new { db = db }
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
        kong.configuration = { vitals = false }

        local vitals = kong_vitals.new { db = db }
        vitals:reset_counters()

        assert.same("vitals not enabled", vitals:log_upstream_latency(7))
      end)

      it("does log upstream latency when vitals is on", function()
        kong.configuration = { vitals = true }

        local vitals = kong_vitals.new { db = db }
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
        local vitals = kong_vitals.new { db = db }
        stub(vitals, "enabled").returns(false)

        assert.same("vitals not enabled", vitals:log_request(nil))
      end)

      it("does log when vitals is on", function()
        local vitals = kong_vitals.new { db = db }
        stub(vitals, "enabled").returns(true)

        vitals:reset_counters()

        local ctx = { authenticated_consumer =  { id = utils.uuid() }}
        local ok, _ = vitals:log_request(ctx)

        assert.not_nil(ok)
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
        seconds_key = now .. "|1|myservice|myroute|200|||"
        minutes_key = (now - (now % 60)) .. "|60|myservice|myroute|200|||"
      end)

      after_each(function()
        vitals.counter_cache:delete(seconds_key)
        vitals.counter_cache:delete(minutes_key)
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

        local seconds = vitals.counter_cache:get(seconds_key)
        local minutes = vitals.counter_cache:get(minutes_key)

        assert.same(1, seconds)
        assert.same(1, minutes)
      end)
    end)

    describe("flush_vitals_cache()", function()
      before_each(function()
        if db.strategy == "cassandra" then
          assert(db:truncate("vitals_consumers"))
          assert(db:truncate("vitals_codes_by_service"))
        end
        assert(db:truncate("vitals_code_classes_by_cluster"))
        assert(db:truncate("vitals_code_classes_by_workspace"))
        assert(db:truncate("vitals_codes_by_route"))
        assert(db:truncate("vitals_codes_by_consumer_route"))
      end)

      after_each(function()
        vitals.counter_cache:flush_all() -- mark expired
        vitals.counter_cache:flush_expired() -- really clean them up
        if db.strategy == "cassandra" then
          assert(db:truncate("vitals_consumers"))
          assert(db:truncate("vitals_codes_by_service"))
        end
        assert(db:truncate("vitals_code_classes_by_cluster"))
        assert(db:truncate("vitals_code_classes_by_workspace"))
        assert(db:truncate("vitals_codes_by_route"))
        assert(db:truncate("vitals_codes_by_consumer_route"))
      end)

      it("flushes cache entries", function()
        stub(vitals, "enabled").returns(true)

        local service_id = utils.uuid()
        local route_id = utils.uuid()
        local consumer_id = utils.uuid()
        local workspace_id = utils.uuid()
        local now = ngx_time()
        local minute = now - (now % 60)

        local cache_entries = {
          (now - 1) .. "|1|" .. service_id .. "|" .. route_id .. "|200|" .. consumer_id .. "|" .. workspace_id .. "|",
          now .. "|1|" .. service_id .. "|" .. route_id .. "|404||" .. workspace_id .. "|",
          minute .. "|60|" .. service_id .. "|" .. route_id .. "|200|" .. consumer_id .. "|" .. workspace_id .. "|",
          minute .. "|60|" .. service_id .. "|" .. route_id .. "|404||" .. workspace_id .. "|",
        }

        for i, v in ipairs(cache_entries) do
          assert(vitals.counter_cache:set(v, i))
        end
        assert.same(4, #vitals.counter_cache:get_keys())

        local res, err = vitals:flush_vitals_cache()
        assert.is_nil(err)
        assert.same(4, res)

        local res, err = vitals:get_status_codes({
          entity_type = "service",
          entity_id   = service_id,
          duration    = "seconds",
          level       = "cluster"
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

        local res, err = vitals:get_status_codes({
          entity_type = "workspace",
          entity_id   = workspace_id,
          duration    = "seconds",
          level       = "cluster"
        })

        assert.is_nil(err)

        local expected = {
          [tostring(now - 1)] = {
            ["2xx"] = 1,
          },
          [tostring(now)] = {
            ["4xx"] = 2,
          }
        }

        assert.same(expected, res.stats.cluster)

        local res, err
        if db.strategy == "postgres" then
          res, err = db.connector:query("SELECT route_id, code, extract('epoch' from at) as at, duration, count FROM vitals_codes_by_route")
        else
          res, err = db.connector:query("select * from vitals_codes_by_route")
        end

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
        if db.strategy == "cassandra" then
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

        local res, err
        if db.strategy == "postgres" then
          res, err = db.connector:query([[
              select code_class, extract('epoch' from at) as at,
              duration, count from vitals_code_classes_by_cluster
           ]])
        else
          res, err = db.connector:query("select * from vitals_code_classes_by_cluster")
        end

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
        if db.strategy == "cassandra" then
          for i, v in ipairs(ats) do
            ats[i] = v * 1000
          end
        end

        local expected = {
          {
            at = ats[1],
            code_class = 2,
            count = 1,
            duration = 1,
          }, {
            at = ats[2],
            code_class = 4,
            count = 2,
            duration = 1,
          }, {
            at = ats[3],
            code_class = 2,
            count = 3,
            duration = 60,
          }, {
            at = ats[4],
            code_class = 4,
            count = 4,
            duration = 60,
          }
        }

        for i = 1, 4 do
          assert.same(expected[i], res[i])
        end

        -- vitals_consumers is cassandra-only
        local res, err
        if db.strategy == "cassandra" then
          res, err = db.connector:query("select * from vitals_consumers")

          assert.is_nil(err)
          table.sort(res, function(a,b)
            return a.count < b.count
          end)

          local ats = {
            now - 1,
            minute,
          }

          for i, v in ipairs(ats) do
            ats[i] = v * 1000
          end

          local expected = {
            {
              at = ats[1],
              consumer_id = consumer_id,
              count = 1,
              duration = 1,
              node_id = vitals.node_id,
            }, {
              at = ats[2],
              consumer_id = consumer_id,
              count = 3,
              duration = 60,
              node_id = vitals.node_id,
            },
          }

          for i = 1, 2 do
            assert.same(expected[i], res[i])
          end
        end

        local res, err

        if db.strategy == "postgres" then
          res, err = db.connector:query("SELECT consumer_id, service_id, route_id, code, extract('epoch' from at) as at, duration, count FROM vitals_codes_by_consumer_route")
        else
          res, err = db.connector:query("select * from vitals_codes_by_consumer_route")
        end

        assert.is_nil(err)
        table.sort(res, function(a,b)
          return a.count < b.count
        end)

        local ats = {
          now - 1,
          minute,
        }

        if db.strategy == "cassandra" then
          for i, v in ipairs(ats) do
            ats[i] = v * 1000
          end
        end

        local expected = {
          {
            at = ats[1],
            consumer_id = consumer_id,
            route_id    = route_id,
            service_id  = service_id,
            code = 200,
            count = 1,
            duration = 1,
          }, {
            at = ats[2],
            consumer_id = consumer_id,
            route_id    = route_id,
            service_id  = service_id,
            code = 200,
            count = 3,
            duration = 60,
          },
        }

        for i = 1, 2 do
          assert.same(expected[i], res[i])
        end

      end)

      it("flushes cache entries (multiple workspaces", function()
        stub(vitals, "enabled").returns(true)

        local workspace_1 = utils.uuid()
        local workspace_2 = utils.uuid()
        local workspace_ids = workspace_1 .. "," .. workspace_2
        local service_id = utils.uuid()
        local route_id = utils.uuid()
        local consumer_id = utils.uuid()
        local now = ngx_time()
        local minute = now - (now % 60)

        local cache_entries = {
          (now - 1) .. "|1|" .. service_id .. "|" .. route_id .. "|200|" .. consumer_id .. "|" .. workspace_ids .. "|",
          now .. "|1|" .. service_id .. "|" .. route_id .. "|404||" .. workspace_1 .. "|",
          minute .. "|60|" .. service_id .. "|" .. route_id .. "|200|" .. consumer_id .. "|" .. workspace_ids .. "|",
          minute .. "|60|" .. service_id .. "|" .. route_id .. "|404||" .. workspace_1 .. "|",
        }

        for i, v in ipairs(cache_entries) do
          assert(vitals.counter_cache:set(v, i))
        end
        assert.same(4, #vitals.counter_cache:get_keys())

        local res, err = vitals:flush_vitals_cache()
        assert.is_nil(err)
        assert.same(4, res)

        local res, err = vitals:get_status_codes({
          entity_type = "workspace",
          entity_id   = workspace_1,
          duration    = "seconds",
          level       = "cluster"
        })

        assert.is_nil(err)

        local expected = {
          [tostring(now - 1)] = {
            ["2xx"] = 1,
          },
          [tostring(now)] = {
            ["4xx"] = 2,
          }
        }

        assert.same(expected, res.stats.cluster)

        local res, err = vitals:get_status_codes({
          entity_type = "workspace",
          entity_id   = workspace_2,
          duration    = "seconds",
          level       = "cluster"
        })

        assert.is_nil(err)

        local expected = {
          [tostring(now - 1)] = {
            ["2xx"] = 1,
          },
        }

        assert.same(expected, res.stats.cluster)
      end)
    end)

    describe("init()", function()
      it("doesn't initialize strategy  when vitals is off", function()
        kong.configuration = { vitals = false }

        local vitals = kong_vitals.new { db = db }
        vitals:reset_counters()

        local s_strategy = spy.on(vitals.strategy, "init")

        vitals:init()

        assert.spy(s_strategy).was_called(0)
      end)
      it("does initialize strategy when vitals is on", function()
        kong.configuration = { vitals = true }

        local vitals = kong_vitals.new({
          db = db,
        })
        vitals:reset_counters()

        local s_strategy = spy.on(vitals.strategy, "init")

        vitals:init()

        assert.spy(s_strategy).was_called(1)
      end)
    end)

    describe("get_consumer_stats() validations", function()
      it("rejects invalid start_ts", function()
        local res, err = vitals:get_consumer_stats({
          consumer_id = utils.uuid(),
          duration    = "seconds",
          level       = "cluster",
          start_ts    = "foo",
        })

        assert.is_nil(res)
        assert.same("Invalid query params: start_ts must be a number", err)
      end)
    end)

    describe("get_consumer_stats()", function()
      local now     = ngx.time()
      local cons_id = utils.uuid()

      after_each(function()
        if db.strategy == "cassandra" then
          assert(db.connector:query("truncate table vitals_consumers"))
        end
        assert(db.connector:query("truncate table vitals_node_meta"))
        assert(db.connector:query("truncate table vitals_codes_by_consumer_route"))
      end)

      it("returns seconds stats for a consumer", function()
        local mock_stats = {
          {
            node_id = "cluster",
            at      = now,
            count   = 1,
          },
          {
            node_id = "cluster",
            at      = now + 1,
            count   = 8,
          },
          {
            node_id = "cluster",
            at      = now + 2,
            count   = 11,
          },
        }

        stub(vitals.strategy, "select_consumer_stats").returns(mock_stats)

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

      it("returns minutes stats for a consumer", function()
        local mock_stats = {
          {
            node_id = "cluster",
            at      = now,
            count   = 39,
          },
          {
            node_id = "cluster",
            at      = now + 60,
            count   = 24,
          },
        }

        stub(vitals.strategy, "select_consumer_stats").returns(mock_stats)

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
        vitals = kong_vitals.new { db = db }
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

      it("rejects invalid start_ts", function()
        local res, err = vitals:get_stats("minutes", "cluster", nil, "foo")

        local expected = "Invalid query params: start_ts must be a number"

        assert.is_nil(res)
        assert.same(expected, err)
      end)

      it("doesn't mind a null start_ts", function()
        local _, err = vitals:get_stats("minutes", "cluster", nil)
        assert.is_nil(err)
      end)

      it("returns converted stats", function()
        local expected = {
          meta = {
            earliest_ts = now,
            interval = "seconds",
            interval_width = 1,
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

    describe("get_status_codes() - validation", function()
      it("rejects invalid query_type", function()
        local res, err = vitals:get_status_codes({
          entity_type = "service",
          duration    = "foo",
          level       = "cluster",
          service_id  = utils.uuid(),
        })

        local expected = "Invalid query params: interval must be 'minutes' or 'seconds'"

        assert.is_nil(res)
        assert.same(expected, err)
      end)

      it("rejects invalid level", function()
        local res, err = vitals:get_status_codes({
          entity_type = "service",
          duration    = "minutes",
          level       = "not_legit",
          service_id  = utils.uuid(),
        })

        local expected = "Invalid query params: level must be 'cluster'"

        assert.is_nil(res)
        assert.same(expected, err)
      end)

      it("rejects invalid start_ts", function()
        local res, err = vitals:get_status_codes({
          level       = "cluster",
          entity_type = "service",
          entity_id   = utils.uuid(),
          duration    = "minutes",
          start_ts    = "foo",
        })

        local expected = "Invalid query params: start_ts must be a number"

        assert.is_nil(res)
        assert.same(expected, err)
      end)

      it("doesn't mind a null start_ts", function()
        local _, err = vitals:get_status_codes({
          level       = "cluster",
          entity_type = "service",
          entity_id   = utils.uuid(),
          duration    = "minutes",
        })

        assert.is_nil(err)
      end)
    end)

    describe("get_status_codes() for cluster", function()
      local vitals
      local now = ngx_time()
      local data_to_insert = {
        { at = now - 1, code_class = 4, count = 10 },
        { at = now, code_class = 4, count = 47 },
        { at = now, code_class = 5, count = 12 },
      }

      setup(function()
        vitals = kong_vitals.new { db = db }
        stub(vitals.strategy, "select_status_codes").returns(data_to_insert)
      end)

      it("rejects invalid query_type", function()
        local res, err = vitals:get_status_codes({
          duration    = "foo",
          level       = "cluster",
          entity_type = "cluster",
        })

        local expected = "Invalid query params: interval must be 'minutes' or 'seconds'"

        assert.is_nil(res)
        assert.same(expected, err)
      end)

      it("rejects invalid level", function()
        local res, err = vitals:get_status_codes({
          duration    = "minutes",
          level       = "not_legit",
          entity_type = "cluster",
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
            entity_type = "cluster",
            stat_labels = {
              "status_code_classes_total",
            },
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
          duration    = "seconds",
          level       = "cluster",
          entity_type = "cluster",
        })

        assert.same(res, expected)
      end)
    end)

    describe("get_status_codes() for service", function()
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
        stub(vitals.strategy, "select_status_codes").returns(data_to_insert)
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
            stat_labels = {
              "status_codes_per_service_total",
            },
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

        local res, _ = vitals:get_status_codes({
          entity_type = "service",
          duration    = "seconds",
          level       = "cluster",
          entity_id   = uuid,
        })

        assert.same(res, expected)
      end)
    end)

    describe("get_status_codes() for workspace", function()
      local now = ngx_time()
      local uuid = utils.uuid()

      local result_set = {
        { workspace_id = uuid, at = now, code_class = 4, count = 5 },
        { workspace_id = uuid, at = now, code_class = 2, count = 533 },
        { workspace_id = uuid, at = now - 1 , code_class = 2, count = 23 },
        { workspace_id = uuid, at = now - 2, code_class = 5, count = 1 },
      }

      setup(function()
        stub(vitals.strategy, "select_status_codes").returns(result_set)
      end)

      it("returns converted stats", function()

        local expected = {
          meta = {
            entity_type = "workspace",
            entity_id = uuid,
            earliest_ts = now - 2,
            interval = "seconds",
            latest_ts = now,
            level = "cluster",
            stat_labels = {
              "status_code_classes_per_workspace_total",
            },
          },
          stats = {
            cluster = {
              [tostring(now - 2)] = {
                ["5xx"] = 1,
              },
              [tostring(now - 1)] = {
                ["2xx"] = 23,
              },
              [tostring(now)] = {
                ["4xx"] = 5,
                ["2xx"] = 533
              },
            }
          }
        }

        local res, _ = vitals:get_status_codes({
          entity_type = "workspace",
          duration    = "seconds",
          level       = "cluster",
          entity_id   = uuid,
        })

        assert.same(res, expected)
      end)
    end)

    describe("get_status_codes() for route", function()
      local now = ngx_time()
      local uuid = utils.uuid()

      local from_db = {
        { route_id = uuid, at = now, code = 400, count = 5 },
        { route_id = uuid, at = now, code = 200, count = 533 },
        { route_id = uuid, at = now - 1 , code = 200, count = 6 },
        { route_id = uuid, at = now - 1 , code = 204, count = 17 },
        { route_id = uuid, at = now - 2, code = 500, count = 1 },
      }

      setup(function()
        stub(vitals.strategy, "select_status_codes").returns(from_db)
      end)

      it("returns converted stats", function()

        local expected = {
          meta = {
            entity_type = "route",
            entity_id = uuid,
            earliest_ts = now - 2,
            interval = "seconds",
            latest_ts = now,
            level = "cluster",
            stat_labels = {
              "status_codes_per_route_total",
            },
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

        local res, _ = vitals:get_status_codes({
          entity_type = "route",
          duration    = "seconds",
          level       = "cluster",
          entity_id   = uuid,
        })

        assert.same(expected, res)
      end)
    end)

    describe("get_status_codes() for consumer_route", function()
      local now = ngx_time()
      local route_id = utils.uuid()
      local service_id = utils.uuid()
      local consumer_id = utils.uuid()

      local from_db = {
        { consumer_id = consumer_id, service_id = service_id, route_id = route_id, at = now, code = 400, count = 10 },
        { consumer_id = consumer_id, service_id = service_id, route_id = route_id, at = now, code = 200, count = 11 },
        { consumer_id = consumer_id, service_id = service_id, route_id = route_id, at = now - 1 , code = 200, count = 5 },
        { consumer_id = consumer_id, service_id = service_id, route_id = route_id, at = now - 1 , code = 204, count = 3 },
        { consumer_id = consumer_id, service_id = service_id, route_id = route_id, at = now - 2, code = 500, count = 1 },
      }

      setup(function()
        stub(vitals.strategy, "select_status_codes").returns(from_db)
      end)

      it("returns converted stats", function()

        local expected = {
          meta = {
            entity_type = "consumer_route",
            entity_id = consumer_id,
            earliest_ts = now - 2,
            interval = "seconds",
            latest_ts = now,
            level = "cluster",
            stat_labels = {
              "status_codes_per_consumer_route_total",
            },
          },
          stats = {
            cluster = {
              [tostring(now - 2)] = {
                ["500"] = 1,
              },
              [tostring(now - 1)] = {
                ["200"] = 5,
                ["204"] = 3,
              },
              [tostring(now)] = {
                ["400"] = 10,
                ["200"] = 11
              },
            }
          }
        }

        local res, _ = vitals:get_status_codes({
          entity_type = "consumer_route",
          duration    = "seconds",
          level       = "cluster",
          entity_id   = consumer_id,
        })

        assert.same(expected, res)
      end)
    end)

    describe("get_node_meta()", function()
      after_each(function()
        assert(db.connector:query("truncate table vitals_node_meta"))
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
          if strategy == "cassandra" then
            assert(vitals.strategy:init(unpack(row)))
          else
            assert(db.connector:query(fmt(q, unpack(row))))
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

end
