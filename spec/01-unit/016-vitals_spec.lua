local conf_loader  = require "kong.conf_loader"
local helpers      = require "spec.helpers"
local dao_factory  = require "kong.dao.factory"
local kong_vitals  = require "kong.vitals"
local singletons   = require "kong.singletons"
local dao_helpers  = require "spec.02-integration.03-dao.helpers"
local ngx_time     = ngx.time


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
    local dao

    setup(function()
      dao = assert(dao_factory.new(kong_conf))

      assert(dao:run_migrations())
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

    describe("current_bucket()", function()
      it("returns the current bucket", function()
        local vitals = kong_vitals.new { dao = dao }
        vitals:reset_counters()

        local res, err = vitals:current_bucket()

        assert.is_nil(err)
        assert.same(0, res)
      end)
      it("only returns good bucket indexes (lower-bound check)", function()
        local vitals = kong_vitals.new { dao = dao }
        vitals:reset_counters()

        vitals.counters = { start_at = ngx_time() + 1 }

        local res, err = vitals:current_bucket()

        assert.same("bucket -1 out of range for counters starting at " .. vitals.counters.start_at, err)
        assert.is_nil(res)
      end)
      it("only returns good bucket indexes (upper-bound check)", function()
        local vitals = kong_vitals.new { dao = dao }
        vitals:reset_counters()

        vitals.counters = { start_at = ngx.time() - 60 }

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
          flush_interval = 60,
          postgres_rotation_interval = 3600,
        })
        vitals:reset_counters()

        local s_strategy = spy.on(vitals.strategy, "init")

        vitals:init()

        assert.spy(s_strategy).was_called(1)
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
