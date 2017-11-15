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


    describe("prepare_counters_for_insert()", function()
      local vitals

      setup(function()
        vitals = kong_vitals.new { dao = dao }

        local at = ngx_time() - 60

        local counter_table = {
          l2_hits           = {},
          l2_misses         = {},
          proxy_latency_min = {},
          proxy_latency_max = {},
          start_at          = at,
        }


        for i=1,60 do
          counter_table.l2_hits[i]           = i
          counter_table.l2_misses[i]         = i
          counter_table.proxy_latency_min[i] = i
          counter_table.proxy_latency_max[i] = i
        end

        vitals.counters = counter_table
      end)

      it("converts counters table to 2-D array", function()
        local res = vitals:prepare_counters_for_insert()

        local expected = {}
        for i=1,60 do
          expected[i] = { vitals.counters.start_at - 1 + i, i, i, i, i }
        end


        assert.same(expected, res)
      end)
    end)
    describe("current_bucket()", function()
      it("returns the current bucket", function()
        local vitals = kong_vitals.new { dao = dao }
        vitals:reset_counters()

        local res, err = vitals:current_bucket()

        assert.is_nil(err)
        assert.same(1, res)
      end)
      it("only returns good bucket indexes (lower-bound check)", function()
        local vitals = kong_vitals.new { dao = dao }
        vitals:reset_counters()

        vitals.counters = { start_at = ngx_time() + 1 }

        local res, err = vitals:current_bucket()

        assert.same("bucket 0 out of range for counters starting at " .. vitals.counters.start_at, err)
        assert.is_nil(res)
      end)
      it("only returns good bucket indexes (upper-bound check)", function()
        local vitals = kong_vitals.new { dao = dao }
        vitals:reset_counters()

        vitals.counters = { start_at = ngx.time() - 60 }

        local res, err = vitals:current_bucket()

        assert.same("bucket 61 out of range for counters starting at " .. vitals.counters.start_at, err)
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
        vitals:reset_counters()

        local initial_l2_counter = vitals.counters["l2_hits"][1]

        vitals:cache_accessed(2)

        assert.same(initial_l2_counter + 1, vitals.counters["l2_hits"][1])
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
        vitals:reset_counters()

        vitals:log_latency(7)
        vitals:log_latency(91)

        assert.same({ 7 }, vitals.counters.proxy_latency_min)
        assert.same({ 91 }, vitals.counters.proxy_latency_max)
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
  end)

end)
