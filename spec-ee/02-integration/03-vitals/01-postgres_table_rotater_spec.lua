local table_rotater = require "kong.vitals.postgres.table_rotater"
local helpers       = require "spec.helpers"
local ngx_time      = ngx.time
local fmt           = string.format


local function drop_vitals_seconds_tables(db)
  local query = [[
  select table_name from information_schema.tables
   where table_schema = 'public'
     and table_name like 'vitals_stats_seconds_%'
  ]]

  local res = db:query(query)

  for i = 1, #res do
    assert(db:query("drop table if exists " .. res[i].table_name))
  end
end


for _, strategy in helpers.each_strategy() do
  if strategy == "cassandra" then
    return
  end

  describe("Postgres table_rotater", function()
    local rotater
    local db, _
    local snapshot


    setup(function()
      _, db, _ = helpers.get_db_utils(strategy)
      db = db.connector

      local opts = {
        connector         = db,
        rotation_interval = 3600,
      }

      rotater = table_rotater.new(opts)
    end)


    before_each(function()
      drop_vitals_seconds_tables(db)
      snapshot = assert:snapshot()
    end)


    after_each(function()
      snapshot:revert()
    end)



    describe(":init()", function()
      it("does not bomb if current table already exists", function()
        -- create current table
        local q = [[
          CREATE TABLE IF NOT EXISTS %s
          (LIKE vitals_stats_seconds INCLUDING defaults INCLUDING constraints INCLUDING indexes);
        ]]

        local query = fmt(q, rotater:current_table_name())
        assert(db:query(query))

        assert(rotater:init())
      end)

      it("does not bomb if postgres thinks it exists", function()
        db = rotater.connector
        stub(db, "query").returns(nil, "typname, typnamespace=already exists with value")

        assert(rotater:init())
      end)
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


    describe(":table_names_for_select()", function()
      it("returns only the current table name when no previous tables exist", function()
        local current = rotater:current_table_name()
        assert(db:query("create table if not exists " .. current .. " (like vitals_stats_seconds)"))

        assert.same({ current }, rotater:table_names_for_select())
      end)

      it("returns the most recent table names when previous tables exist", function()

        local now = ngx_time()
        local previous = "vitals_stats_seconds_" .. (now - (now % 3600) - 3600)

        local current = rotater:current_table_name()

        assert(db:query("create table if not exists " .. current .. " (like vitals_stats_seconds)"))
        assert(db:query("create table if not exists " .. previous .. " (like vitals_stats_seconds)"))

        local res = rotater:table_names_for_select()

        assert.same({ current, previous }, res)
      end)

      it("does not return older table names", function()
        assert(db:query("create table if not exists vitals_stats_seconds_1505865600 (like vitals_stats_seconds)"))

        local res = rotater:table_names_for_select()

        assert.same({}, res)
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
      local table_names

      before_each(function()
        -- test setup assumes rotation interval is 3600. fail if not
        assert.same(3600, rotater.rotation_interval)

        local now = ngx_time()
        local current_ts = now - (now % 3600)

        -- one table we can drop,
        -- two we are currently querying,
        -- one for the upcoming inserts
        table_names = {
          "vitals_stats_seconds_" .. tostring(current_ts - 7200),
          "vitals_stats_seconds_" .. tostring(current_ts - 3600),
          "vitals_stats_seconds_" .. tostring(current_ts),
          "vitals_stats_seconds_" .. tostring(current_ts + 3600),
        }

        for _, v in ipairs(table_names) do
          assert(db:query("create table if not exists " .. v ..
              " (like vitals_stats_seconds including defaults including constraints including indexes)"))
        end
      end)

      it("drops only old tables (keeping the current 2 and future 1)", function()
        rotater:drop_previous_table()

        local query = "select table_name from information_schema.tables " ..
            "where table_schema = 'public' and table_name in ('" ..
            table_names[1] .. "', '" ..
            table_names[2] .. "', '" ..
            table_names[3] .. "', '" ..
            table_names[4] .. "') " ..
            "order by table_name"

        local res, _ = db:query(query)
        local expected = {
          { table_name = table_names[2] },
          { table_name = table_names[3] },
          { table_name = table_names[4] },
        }

        assert.same(expected, res)
      end)
    end)
  end)
end
