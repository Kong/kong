local conf_loader  = require "kong.conf_loader"
local helpers      = require "spec.helpers"
local dao_factory  = require "kong.dao.factory"
local kong_vitals  = require "kong.vitals"
local singletons   = require "kong.singletons"
local dao_helpers  = require "spec.02-integration.03-dao.helpers"
local utils        = require "kong.tools.utils"

local ngx_time     = ngx.time
local fmt          = string.format


dao_helpers.for_each_dao(function(kong_conf)
  if kong_conf.database == "cassandra" then
    it("errors if vitals=on and database=cassandra", function()
      local _, result = conf_loader(helpers.test_conf_path, {
        database = "cassandra",
        vitals   = true,
      })

      local expected = "vitals: not available on cassandra. Restart with vitals=off."

      assert.same(expected, result)
    end)

    return
  end


  describe("vitals with db: " .. kong_conf.database, function()
    local vitals
    local dao

    setup(function()
      dao = assert(dao_factory.new(kong_conf))
      assert(dao:run_migrations())

      vitals = kong_vitals.new({
        dao = dao,
      })
    end)

    describe("flush_lock()", function()
      before_each(function()
        ngx.shared.kong:delete("vitals:flush_lock")
      end)

      teardown(function()
        ngx.shared.kong:delete("vitals:flush_lock")

        local v = ngx.shared.kong:get("vitals:flush_lock")
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
          "vitals_consumers",
          "vitals_node_meta",
          "vitals_stats_hours",
          "vitals_stats_minutes",
          "vitals_stats_seconds",
        }

        if (dao.db_type == "postgres") then
          expected[6] = "vitals_stats_seconds_foo"
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

      it("only returns good bucket indexes (upper-bound check)", function()
        local vitals = kong_vitals.new({
          dao            = dao,
          flush_interval = 60,
        })

        vitals.counters.start_at = ngx.time() - 60

        local res, err = vitals:current_bucket()

        assert.same("bucket 60 out of range for counters starting at " .. vitals.counters.start_at, err)
        assert.is_nil(res)
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

      before_each(function()
        local q, query

        q = "insert into vitals_consumers(consumer_id, node_id, start_at, duration, count) " ..
            "values('%s', '%s', to_timestamp(%d), %d, %d)"

        local data_to_insert = {
          {cons_id, node_1, 1510560000, 1, 1},
          {cons_id, node_1, 1510560001, 1, 3},
          {cons_id, node_1, 1510560002, 1, 4},
          {cons_id, node_1, 1510560000, 60, 19},
          {cons_id, node_2, 1510560001, 1, 5},
          {cons_id, node_2, 1510560002, 1, 7},
          {cons_id, node_2, 1510560000, 60, 20},
          {cons_id, node_2, 1510560060, 60, 24},
        }

        for _, row in ipairs(data_to_insert) do
          query = fmt(q, unpack(row))
          assert(dao.db:query(query))
        end
      end)

      after_each(function()
        assert(dao.db:query("truncate table vitals_consumers"))
      end)

      it("returns seconds stats for a consumer across the cluster", function()
        local res, _ = vitals:get_consumer_stats({
          consumer_id = cons_id,
          duration    = "seconds",
          level       = "cluster",
        })

        local expected = {
          meta = {
            interval = 'seconds',
            consumer = {
              id = cons_id
            },
          },
          stats = {
            cluster = {
              ["1510560000"] = 1,
              ["1510560001"] = 8,
              ["1510560002"] = 11,
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
            interval = 'seconds',
            node     = {
              id = node_1,
            },
            consumer = {
              id = cons_id,
            },
          },
          stats = {
            [node_1] = {
              ["1510560000"] = 1,
              ["1510560001"] = 3,
              ["1510560002"] = 4,
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
            interval = 'minutes',
            consumer = {
              id = cons_id
            },
          },
          stats = {
            cluster = {
              ["1510560000"] = 39,
              ["1510560060"] = 24,
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
            interval = 'minutes',
            node     = {
              id = node_2,
            },
            consumer = {
              id = cons_id,
            },
          },
          stats = {
            [node_2] = {
              ["1510560000"] = 20,
              ["1510560060"] = 24,
            }
          }
        }

        assert.same(expected, res)
      end)
    end)

    describe("select_stats()", function()
      local vitals
      setup(function()
        vitals = kong_vitals.new { dao = dao }
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
    end)
  end)

end)
