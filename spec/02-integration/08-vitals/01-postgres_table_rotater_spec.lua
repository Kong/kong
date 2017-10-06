local table_rotater = require "kong.vitals.postgres.table_rotater"
local dao_factory   = require "kong.dao.factory"
local dao_helpers   = require "spec.02-integration.03-dao.helpers"
local ngx_time      = ngx.time


dao_helpers.for_each_dao(function(kong_conf)
  if kong_conf.database == "cassandra" then
    return
  end

  describe("Postgres table_rotater", function()
    local rotater
    local dao
    local db
    local snapshot


    setup(function()
      dao = assert(dao_factory.new(kong_conf))
      db  = dao.db


      local opts = {
        db                = db,
        rotation_interval = 3600,
      }

      rotater = table_rotater.new(opts)
    end)


    before_each(function()
      snapshot = assert:snapshot()
    end)


    after_each(function()
      snapshot:revert()
    end)


    describe(":current_table_name()", function()
      it("returns the table name for the current hour", function()
        -- what I really want to do here is to stub ngx.time() so that
        -- I can test edge cases such as on the hour, daylight savings
        -- boundaries, and leap seconds
        local now          = ngx_time()
        local current_hour = now - (now % 3600)
        local expected     = "vitals_stats_seconds_" .. current_hour

        assert.same(expected, rotater:current_table_name())
      end)
    end)


    describe(":create_next_table()", function()
      it("creates a table for the upcoming hour", function()
        local now       = ngx_time()
        local next_hour = now + 3600 - (now % 3600)
        local expected  = "vitals_stats_seconds_" .. tostring(next_hour)

        assert.same(expected, rotater:create_next_table())
      end)


      it("does not error if the table already exists", function()
        local now       = ngx_time()
        local next_hour = now + 3600 - (now % 3600)
        local expected  = "vitals_stats_seconds_" .. next_hour


        -- make sure next table is already there
        assert(rotater:create_next_table())


        assert.same(expected, rotater:create_next_table())
      end)
    end)


    describe(":drop_previous_table()", function()
      it("drops all tables prior to current one", function()
        assert(db:query("create table if not exists vitals_stats_seconds_1505865600 (like vitals_stats_seconds)"))
        assert(db:query("create table if not exists vitals_stats_seconds_1505862000 (like vitals_stats_seconds)"))
        assert(db:query("create table if not exists vitals_stats_seconds_1505858400 (like vitals_stats_seconds)"))

        stub(rotater.aggregator, "aggregate_minutes").returns("ok response for tests")

        rotater:drop_previous_table()


        local query = [[
          select table_name from information_schema.tables
          where table_schema = 'public' and table_name in (
            'vitals_stats_seconds_1505865600',
            'vitals_stats_seconds_1505862000',
            'vitals_stats_seconds_1505858400')
        ]]

        local res, err = db:query(query)

        assert.is_nil(err)
        assert.equals(0, #res)
      end)


      it("does not drop tables at or after current one", function()
        -- initialize current and future tables
        rotater:init()

        stub(rotater.aggregator, "aggregate_minutes").returns("ok response for tests")

        rotater:drop_previous_table()


        local query = [[
        select table_name from information_schema.tables
         where table_schema = 'public'
           and table_name like 'vitals_stats_seconds_%'
           and table_name >= '
        ]] .. rotater:current_table_name() .. "'"

        local res, err = db:query(query)

        assert.is_nil(err)
        assert.equals(2, #res)
      end)


      it("does not drop table if it couldn't aggregate minutes", function()
        assert(db:query("create table if not exists vitals_stats_seconds_1505865600 (like vitals_stats_seconds)"))

        stub(rotater.aggregator, "aggregate_minutes").returns(nil, "stubbed error for tests")

        rotater:drop_previous_table()


        local query = [[
        select table_name from information_schema.tables
         where table_schema = 'public'
           and table_name = 'vitals_stats_seconds_1505865600'
        ]]

        local res, err = db:query(query)

        assert.is_nil(err)
        assert.equals(1, #res)
      end)
    end)
  end)
end)
