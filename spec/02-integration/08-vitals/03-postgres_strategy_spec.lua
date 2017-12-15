local pg_strategy = require "kong.vitals.postgres.strategy"
local dao_factory = require "kong.dao.factory"
local helpers     = require "spec.helpers"
local dao_helpers = require "spec.02-integration.03-dao.helpers"
local utils       = require "kong.tools.utils"
local fmt         = string.format
local time        = ngx.time


dao_helpers.for_each_dao(function(kong_conf)
  if kong_conf.database == "cassandra" then
    return
  end


  describe("Postgres strategy", function()
    local strategy
    local dao
    local db
    local snapshot


    setup(function()
      helpers.run_migrations()

      dao      = assert(dao_factory.new(kong_conf))
      strategy = pg_strategy.new(dao)

      db  = dao.db

      -- simulate a "previous" seconds table
      assert(db:query("create table if not exists vitals_stats_seconds_2 " ..
             "(like vitals_stats_seconds including defaults including constraints including indexes)"))
    end)


    before_each(function()
      snapshot = assert:snapshot()

      assert(db:query("truncate table vitals_stats_minutes"))
      assert(db:query("truncate table vitals_stats_seconds"))
      assert(db:query("truncate table vitals_stats_seconds_2"))
      assert(db:query("truncate table vitals_node_meta"))
      assert(db:query("truncate table vitals_consumers"))
    end)


    after_each(function()
      snapshot:revert()
    end)


    describe(":init()", function()
      it("inserts node metadata", function()

        local node_id  = utils.uuid()
        local hostname = "testhostname"

        assert(strategy:init(node_id, hostname))

        local res, _ = db:query("select * from vitals_node_meta where node_id = '{" .. node_id .. "}'")

        assert.same(1, #res)
        assert.same("testhostname", res[1].hostname)
        assert.not_nil(res[1].first_report)
        assert.same(res[1].first_report, res[1].last_report)
      end)
    end)


    describe(":insert_stats()", function()
      it("turns Lua tables into Postgres rows", function()
        stub(strategy, "current_table_name").returns("vitals_stats_seconds")


        local data = {
          { 1505964713, 0, 0, nil, nil, nil, nil, 0 },
          { 1505964714, 19, 99, 0, 120, 12, 47, 7 },
        }

        local node_id = utils.uuid()

        strategy:init(node_id, "testhostname")

        assert(strategy:insert_stats(data))

        local res, _ = db:query("select * from vitals_stats_seconds")

        local expected = {
          {
            at       = 1505964713,
            node_id  = node_id,
            l2_hit   = 0,
            l2_miss  = 0,
            requests = 0
          },
          {
            at       = 1505964714,
            node_id  = node_id,
            l2_hit   = 19,
            l2_miss  = 99,
            plat_min = 0,
            plat_max = 120,
            ulat_min = 12,
            ulat_max = 47,
            requests = 7
          },
        }
        assert.same(expected, res)

        local res, _ = db:query("select * from vitals_stats_minutes")

        local expected = {
          {
            at       = 1505964660,
            node_id  = node_id,
            l2_hit   = 19,
            l2_miss  = 99,
            plat_min = 0,
            plat_max = 120,
            ulat_min = 12,
            ulat_max = 47,
            requests = 7
          }
        }

        assert.same(expected, res)
      end)

      it("records the last_report time for this node", function()
        stub(strategy, "current_table_name").returns("vitals_stats_seconds")


        local data = {
          { 1505964713, 0, 0, nil, nil, nil, nil, 0 },
          { 1505964714, 19, 99, 0, 120, 12, 47, 15 },
        }

        local node_id = utils.uuid()

        strategy:init(node_id, "testhostname")

        local report_q = "select last_report from vitals_node_meta where node_id = '{" .. node_id .. "}'"

        local res, _   = db:query(report_q)
        local orig_rep = res[1].last_report

        assert(strategy:insert_stats(data))

        local res, _  = db:query(report_q)
        local new_rep = res[1].last_report

        assert.not_same(new_rep, orig_rep)
      end)
    end)


    describe(":select_stats()", function()
      local node_1 = "20426633-55dc-4050-89ef-2382c95a611e"
      local node_2 = "8374682f-17fd-42cb-b1dc-7694d6f65ba0"

      before_each(function()
        local q, query
        local at = 1509667484

        -- add some data we can query
        for i = 1, 2 do
          q = "insert into %s(at, node_id, l2_hit, l2_miss, " ..
              "plat_min, plat_max, ulat_min, ulat_max, requests) values(%d, '{%s}', %d, %d, %s, %s, %s, %s, %d)"

          query = fmt(q, "vitals_stats_seconds", at + i, node_1, i + 3, i, i, i * 10, i + 2, i * 7, i + 1)
          assert(db:query(query))

          query = fmt(q, "vitals_stats_seconds", at + i, node_2, i + 5, i + 1, i, i * 5, i + 3, i * 4, i + 3)
          assert(db:query(query))

          query = fmt(q, "vitals_stats_minutes", at + i, node_1, i + 10, i + 20, 0, i * 20, i, i * 9, i + 6)
          assert(db:query(query))

          query = fmt(q, "vitals_stats_minutes", at + i, node_2, i + 2, i + 7, i, i * 6, i + 5, i * 8, i + 14)
          assert(db:query(query))
        end

        -- include some null data
        query = fmt(q, "vitals_stats_seconds", at + 3, node_1, 19, 23, "null", "null", "null", "null", 14)
        assert(db:query(query))

        query = fmt(q, "vitals_stats_minutes", at + 3, node_1, 19, 23, "null", "null", "null", "null", 14)
        assert(db:query(query))

        -- put some data in the previous seconds table
        at = at - 60

        query = fmt(q, "vitals_stats_seconds_2", at, node_1, 3, 5, 7, 9, 8, 12, 6)
        assert(db:query(query))

        query = fmt(q, "vitals_stats_seconds_2", at, node_2, 2, 4, 6, 8, 4, 16, 17)
        assert(db:query(query))
      end)

      it("returns seconds stats for a node", function()
        stub(strategy, "table_names_for_select").returns({ "vitals_stats_seconds", "vitals_stats_seconds_2"})

        local res, err = strategy:select_stats("seconds", "node", node_1)

        assert.is_nil(err)

        local expected = {
          {
            node_id = node_1,
            at = 1509667424,
            l2_hit = 3,
            l2_miss = 5,
            plat_min = 7,
            plat_max = 9,
            ulat_min = 8,
            ulat_max = 12,
            requests = 6,
          }, {
            node_id = node_1,
            at = 1509667485,
            l2_hit = 4,
            l2_miss = 1,
            plat_min = 1,
            plat_max = 10,
            ulat_min = 3,
            ulat_max = 7,
            requests = 2,
          }, {
            node_id = node_1,
            at = 1509667486,
            l2_hit = 5,
            l2_miss = 2,
            plat_min = 2,
            plat_max = 20,
            ulat_min = 4,
            ulat_max = 14,
            requests = 3,
          }, {
            node_id = node_1,
            at = 1509667487,
            l2_hit = 19,
            l2_miss = 23,
            requests = 14,
          }
        }

        assert.same(expected, res)
      end)

      it("returns minutes stats for a node", function()
        local res, err = strategy:select_stats("minutes", "node", node_1)

        assert.is_nil(err)

        local expected = {
          {
            node_id = node_1,
            at = 1509667485,
            l2_hit = 11,
            l2_miss = 21,
            plat_max = 20,
            plat_min = 0,
            ulat_min = 1,
            ulat_max = 9,
            requests = 7,
          }, {
            node_id = node_1,
            at = 1509667486,
            l2_hit = 12,
            l2_miss = 22,
            plat_max = 40,
            plat_min = 0,
            ulat_min = 2,
            ulat_max = 18,
            requests = 8,
          }, {
            node_id = node_1,
            at = 1509667487,
            l2_hit = 19,
            l2_miss = 23,
            requests = 14,
          }
        }

        assert.same(expected, res)
      end)

      it("returns seconds stats for all nodes", function()
        stub(strategy, "table_names_for_select").returns({ "vitals_stats_seconds", "vitals_stats_seconds_2"})

        local res, err = strategy:select_stats("seconds", "node")

        -- we can't guarantee the sort order coming out since we can't sort
        -- by uuid. just assert we haven't left out any rows.
        assert.is_nil(err)
        assert.equals(7, #res)
      end)

      it("returns minutes stats for all nodes", function()
        local res, err = strategy:select_stats("minutes", "node")

        assert.is_nil(err)

        local expected = {
          {
            at = 1509667485,
            l2_hit = 11,
            l2_miss = 21,
            node_id = node_1,
            plat_max = 20,
            plat_min = 0,
            ulat_min = 1,
            ulat_max = 9,
            requests = 7,
          }, {
            at = 1509667485,
            l2_hit = 3,
            l2_miss = 8,
            node_id = node_2,
            plat_max = 6,
            plat_min = 1,
            ulat_min = 6,
            ulat_max = 8,
            requests = 15,
          }, {
            at = 1509667486,
            l2_hit = 12,
            l2_miss = 22,
            node_id = node_1,
            plat_max = 40,
            plat_min = 0,
            ulat_min = 2,
            ulat_max = 18,
            requests = 8,
          },  {
            at = 1509667486,
            l2_hit = 4,
            l2_miss = 9,
            node_id = node_2,
            plat_max = 12,
            plat_min = 2,
            ulat_min = 7,
            ulat_max = 16,
            requests = 16,
          }, {
            at = 1509667487,
            l2_hit = 19,
            l2_miss = 23,
            node_id = node_1,
            requests = 14,
          }
        }

        assert.same(expected, res)
      end)

      it("returns seconds stats for a cluster", function()
        stub(strategy, "table_names_for_select").returns({ "vitals_stats_seconds", "vitals_stats_seconds_2"})

        local res, err = strategy:select_stats("seconds", "cluster")

        assert.is_nil(err)

        local expected = {
          {
            at = 1509667424,
            node_id = 'cluster',
            l2_hit = 5,
            l2_miss = 9,
            plat_min = 6,
            plat_max = 9,
            ulat_min = 4,
            ulat_max = 16,
            requests = 23,
          }, {
            at = 1509667485,
            node_id = 'cluster',
            l2_hit = 10,
            l2_miss = 3,
            plat_min = 1,
            plat_max = 10,
            ulat_min = 3,
            ulat_max = 7,
            requests = 6,
          }, {
            at = 1509667486,
            node_id = 'cluster',
            l2_hit = 12,
            l2_miss = 5,
            plat_min = 2,
            plat_max = 20,
            ulat_min = 4,
            ulat_max = 14,
            requests = 8,
          }, {
            at = 1509667487,
            node_id = 'cluster',
            l2_hit = 19,
            l2_miss = 23,
            requests = 14,
          }
        }

        assert.same(expected, res)
      end)

      it("returns minutes stats for a cluster", function()
        local res, err = strategy:select_stats("minutes", "cluster")

        assert.is_nil(err)

        local expected = {
          {
            at = 1509667485,
            node_id = 'cluster',
            l2_hit = 14,
            l2_miss = 29,
            plat_max = 20,
            plat_min = 0,
            ulat_min = 1,
            ulat_max = 9,
            requests = 22,
          }, {
            at = 1509667486,
            node_id = 'cluster',
            l2_hit = 16,
            l2_miss = 31,
            plat_max = 40,
            plat_min = 0,
            ulat_min = 2,
            ulat_max = 18,
            requests = 24,
          }, {
            at = 1509667487,
            node_id = 'cluster',
            l2_hit = 19,
            l2_miss = 23,
            requests = 14,
          }
        }

        assert.same(expected, res)
      end)
    end)


    describe(":delete_stats()", function()
      it("validates arguments", function()
        local res, err = strategy:delete_stats()
        assert.is_nil(res)
        assert.same(err, "cutoff_times is required")

        res, err = strategy:delete_stats({})
        assert.is_nil(res)
        assert.same(err, "cutoff_times.minutes must be a number")

        res, err = strategy:delete_stats({ cutoff_times = "foo" })
        assert.is_nil(res)
        assert.same(err, "cutoff_times.minutes must be a number")
      end)

      it("deletes stale data", function()
        local node_id = utils.uuid()
        local now = time()

        local data_to_insert = {
          {now - 4000, 1, 1, 1, 1, 1, 1, 1 },
          {now, 2, 2, 2, 2, 2, 2, 2 },
        }

        strategy:insert_stats(data_to_insert, node_id)

        -- remove everything older than one hour
        local res, err = strategy:delete_stats({ minutes = 3600 })

        assert.same(1, res)
        assert.is_nil(err)
      end)
    end)


    describe(":insert_consumer_stats()", function()
      it("turns Lua tables into Postgres rows", function()
        local node_id = utils.uuid()
        local con1_id = utils.uuid()
        local con2_id = utils.uuid()

        strategy:init(node_id, "testhostname")

        local data_to_insert = {
          {con1_id, 1510560000, 1, 1},
          {con1_id, 1510560001, 1, 3},
          {con2_id, 1510560001, 1, 2},
        }

        assert(strategy:insert_consumer_stats(data_to_insert))

        -- force a sort order to make assertion easier
        local q = [[
            select consumer_id, node_id, extract('epoch' from start_at) as start_at,
                   duration, count from vitals_consumers
            order by start_at, duration, count
        ]]

        local results = db:query(q)

        local expected = {
          {
            consumer_id = con1_id,
            node_id     = node_id,
            start_at    = 1510560000,
            duration    = 1,
            count       = 1,
          },
          {
            consumer_id = con2_id,
            node_id     = node_id,
            start_at    = 1510560000,
            duration    = 60,
            count       = 2,
          },
          {
            consumer_id = con1_id,
            node_id     = node_id,
            start_at    = 1510560000,
            duration    = 60,
            count       = 4,
          },
          {
            consumer_id = con2_id,
            node_id     = node_id,
            start_at    = 1510560001,
            duration    = 1,
            count       = 2,
          },
          {
            consumer_id = con1_id,
            node_id     = node_id,
            start_at    = 1510560001,
            duration    = 1,
            count       = 3,
          },
        }

        assert.same(expected, results)
      end)


      it("upserts when necessary", function()
        local node_id = utils.uuid()
        local con1_id = utils.uuid()

        strategy:init(node_id, "testhostname")

        -- insert a row to upsert on
        assert(strategy:insert_consumer_stats({{ con1_id, 1510560001, 1, 1 }}))


        local data_to_insert = {
          {con1_id, 1510560003, 1, 19},
        }

        assert(strategy:insert_consumer_stats(data_to_insert))

        local q = [[
            select consumer_id, node_id, extract('epoch' from start_at) as start_at,
                   duration, count from vitals_consumers where duration = 60
        ]]

        local results = db:query(q)

        local expected = {
          {
            consumer_id = con1_id,
            node_id     = node_id,
            start_at    = 1510560000,
            duration    = 60,
            count       = 20,
          },
        }

        assert.same(expected, results)
      end)
    end)


    describe(":select_consumer_stats()", function()
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
          assert(db:query(query))
        end

        strategy:init(node_1, "testhostname")
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
            start_at    = 1510560000,
            count       = 1,
          },
          {
            node_id     = "cluster",
            start_at    = 1510560001,
            count       = 8,
          },
          {
            node_id     = "cluster",
            start_at    = 1510560002,
            count       = 11,
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

        assert.same(5, #results)

        -- just to make it easier to assert
        table.sort(results, function(a,b)
          return a.count < b.count
        end)

        local expected = {
          {
            count = 1,
            node_id = node_1,
            start_at = 1510560000,
          },
          {
            count = 3,
            node_id = node_1,
            start_at = 1510560001,
          },
          {
            count = 4,
            node_id = node_1,
            start_at = 1510560002,
          },
          {
            count = 5,
            node_id = node_2,
            start_at = 1510560001,
          },
          {
            count = 7,
            node_id = node_2,
            start_at = 1510560002,
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
            count = 5,
            node_id = node_2,
            start_at = 1510560001,
          },
          {
            count = 7,
            node_id = node_2,
            start_at = 1510560002,
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
            start_at    = 1510560000,
            count       = 39,
          },
          {
            node_id     = "cluster",
            start_at    = 1510560060,
            count       = 24,
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

        assert.same(3, #results)

        table.sort(results, function(a,b)
          return a.count < b.count
        end)


        local expected = {
          {
            count = 19,
            node_id = node_1,
            start_at = 1510560000,
          },
          {
            count = 20,
            node_id = node_2,
            start_at = 1510560000,
          },
          {
            count = 24,
            node_id = node_2,
            start_at = 1510560060,
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
            count = 20,
            node_id = node_2,
            start_at = 1510560000,
          },
          {
            count = 24,
            node_id = node_2,
            start_at = 1510560060,
          },
        }

        assert.same(expected, results)
      end)
    end)


    describe(":delete_consumer_stats()", function()
      local cons_1 = "20426633-55dc-4050-89ef-2382c95a611e"
      local cons_2 = "8374682f-17fd-42cb-b1dc-7694d6f65ba0"
      local node_1 = utils.uuid()

      before_each(function()
        local q, query

        q = "insert into vitals_consumers(consumer_id, node_id, start_at, duration, count) " ..
            "values('%s', '%s', to_timestamp(%d), %d, %d)"

        local test_data = {
          {cons_1, node_1, 1510560000, 1, 1},
          {cons_1, node_1, 1510560001, 1, 3},
          {cons_1, node_1, 1510560002, 1, 4},
          {cons_1, node_1, 1510560000, 60, 19},
          {cons_2, node_1, 1510560001, 1, 5},
          {cons_2, node_1, 1510560002, 1, 7},
          {cons_2, node_1, 1510560000, 60, 20},
          {cons_2, node_1, 1510560060, 60, 24},
        }

        for _, row in ipairs(test_data) do
          query = fmt(q, unpack(row))
          assert(db:query(query))
        end

        strategy:init(node_1, "testhostname")
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

        local results, _ = strategy:delete_consumer_stats(consumers, cutoff_times)

        assert.same(5, results)
      end)
    end)
  end)
end)
