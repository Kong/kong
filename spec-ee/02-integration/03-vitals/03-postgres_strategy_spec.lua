local pg_strategy = require "kong.vitals.postgres.strategy"
local dao_helpers = require "spec.02-integration.03-dao.helpers"
local utils       = require "kong.tools.utils"
local helpers     = require "spec.helpers"
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
      local opts = {
        ttl_seconds = 3600,
        ttl_minutes = 90000,
        delete_interval = 90000,
      }

      dao = select(3, helpers.get_db_utils(kong_conf.database))
      strategy = pg_strategy.new(dao, opts)

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
      assert(db:query("truncate table vitals_code_classes_by_cluster"))
      assert(db:query("truncate table vitals_code_classes_by_workspace"))
      assert(db:query("truncate table vitals_codes_by_route"))
      assert(db:query("truncate table vitals_codes_by_consumer_route"))
      assert(db:query("truncate table vitals_locks"))
      assert(db:query("INSERT INTO vitals_locks(key, expiry) VALUES ('delete_status_codes', NULL)"))
    end)


    after_each(function()
      snapshot:revert()
    end)


    teardown(function()
      assert(db:query("truncate table vitals_stats_minutes"))
      assert(db:query("truncate table vitals_stats_seconds"))
      assert(db:query("truncate table vitals_stats_seconds_2"))
      assert(db:query("truncate table missing_seconds_table"))
      assert(db:query("truncate table vitals_node_meta"))
      assert(db:query("truncate table vitals_code_classes_by_cluster"))
      assert(db:query("truncate table vitals_code_classes_by_workspace"))
      assert(db:query("truncate table vitals_codes_by_route"))
      assert(db:query("truncate table vitals_codes_by_consumer_route"))
      assert(db:query("truncate table vitals_locks"))
      assert(db:query("INSERT INTO vitals_locks(key, expiry) VALUES ('delete_status_codes', NULL)"))
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

    describe("delete_lock()", function()
      before_each(function()
        strategy.list_cache:delete("postgres:delete_lock")
      end)

      teardown(function()
        strategy.list_cache:delete("postgres:delete_lock")

        local v = strategy.list_cache:get("postgres:delete_lock")
        assert.is_nil(v)
      end)

      it("returns true upon acquiring a lock", function()
        local ok, err = strategy:delete_lock(10)

        assert.is_true(ok)
        assert.is_nil(err)
      end)

      it("returns false when failing to acquire a lock, without err", function()
        local ok, err = strategy:delete_lock(10)
        assert.is_true(ok)
        assert.is_nil(err)

        local ok, err = strategy:delete_lock(10)
        assert.is_false(ok)
        assert.is_nil(err)
      end)
    end)

    describe("acquire_lock_status_codes_delete()", function()
      before_each(function()
        strategy.list_cache:delete("postgres:delete_lock")
      end)

      teardown(function()
        strategy.list_cache:delete("postgres:delete_lock")

        local v = strategy.list_cache:get("postgres:delete_lock")
        assert.is_nil(v)
      end)

      it("returns true if acquires both shm and cluster wide locks", function()
        local now = time()
        local when = 10

        local ok, err = strategy:acquire_lock_status_codes_delete(now, when)
        assert.is_true(ok)
        assert.is_nil(err)
      end)

      it("returns false if fails to acquire shm lock", function()
        local now = time()
        local when = 10

        local ok, err = strategy:delete_lock(when)
        assert.is_true(ok)
        assert.is_nil(err)

        local ok, err = strategy:acquire_lock_status_codes_delete(now, when)

        assert.is_false(ok)
        assert.is_nil(err)
      end)

      it("returns false if fails to acquire cluster wide lock", function()
        local now = time()
        local when = 10

        stub(strategy, "delete_lock").returns(true)
        local ok, err = strategy:acquire_lock_status_codes_delete(now, when)
        assert.is_true(ok)
        assert.is_nil(err)

        local ok, err = strategy:acquire_lock_status_codes_delete(now, when)
        assert.is_false(ok)
        assert.is_nil(err)
      end)
    end)


    describe(":insert_stats()", function()
      it("turns Lua tables into Postgres rows", function()
        stub(strategy, "current_table_name").returns("vitals_stats_seconds")

        local data = {
          { 1505964713, 0, 0, nil, nil, nil, nil, 0, 0, 0, 0, 0 },
          { 1505964714, 19, 99, 0, 120, 12, 47, 7, 7, 294, 6, 193 },
        }

        local node_id = utils.uuid()

        assert(strategy:insert_stats(data, node_id))

        local res, _ = db:query("select * from vitals_stats_seconds")

        local expected = {
          {
            at       = 1505964713,
            node_id  = node_id,
            l2_hit   = 0,
            l2_miss  = 0,
            requests = 0,
            plat_count = 0,
            plat_total = 0,
            ulat_count = 0,
            ulat_total = 0,
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
            requests = 7,
            plat_count = 7,
            plat_total = 294,
            ulat_count = 6,
            ulat_total = 193,
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
            requests = 7,
            plat_count = 7,
            plat_total = 294,
            ulat_count = 6,
            ulat_total = 193,
          }
        }

        assert.same(expected, res)
      end)

      it("records the last_report time for this node", function()
        stub(strategy, "current_table_name").returns("vitals_stats_seconds")

        local data = {
          { 1505964713, 0, 0, nil, nil, nil, nil, 0, 0, 0, 0, 0 },
          { 1505964714, 19, 99, 0, 120, 12, 47, 7, 7, 294, 6, 193 },
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

      it("will attempt to create a missing seconds table if an insert fails", function()
        stub(strategy, "current_table_name").returns("missing_seconds_table")

        local data = {
          { 1505964713, 0, 0, nil, nil, nil, nil, 0, 0, 0, 0, 0 },
          { 1505964714, 19, 99, 0, 120, 12, 47, 7, 7, 294, 6, 193 },
        }

        local node_id = utils.uuid()

        assert(strategy:insert_stats(data, node_id))

        local res, _ = db:query("select * from missing_seconds_table")

        local expected = {
          {
            at       = 1505964713,
            node_id  = node_id,
            l2_hit   = 0,
            l2_miss  = 0,
            requests = 0,
            plat_count = 0,
            plat_total = 0,
            ulat_count = 0,
            ulat_total = 0,
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
            requests = 7,
            plat_count = 7,
            plat_total = 294,
            ulat_count = 6,
            ulat_total = 193,
          },
        }
        assert.same(expected, res)
      end)
    end)


    describe(":select_stats()", function()
      local node_1 = "20426633-55dc-4050-89ef-2382c95a611e"
      local node_2 = "8374682f-17fd-42cb-b1dc-7694d6f65ba0"

      before_each(function()
        local q, query
        local at = 1509667484

        -- add some data we can query
        local test_data = {
          { "vitals_stats_seconds", at + 1, node_1, 4, 1, 1, 10, 3, 7, 2, 2, 33, 2, 12, },
          { "vitals_stats_seconds", at + 1, node_2, 6, 2, 1, 5, 4, 4, 4, 4, 10, 4, 13, },
          { "vitals_stats_seconds", at + 2, node_1, 5, 2, 2, 20, 4, 14, 3, 3, 34, 3, 28, },
          { "vitals_stats_seconds", at + 2, node_2, 7, 3, 2, 10, 5, 8, 5, 5, 40, 4, 19, },
          { "vitals_stats_seconds", at + 3, node_1, 19, 23, "null", "null", "null", "null", 14, 0, 0, 0, 0, },

          { "vitals_stats_minutes", at + 1, node_1, 11, 21, 0, 20, 1, 9, 7, 7, 42, 6, 34, },
          { "vitals_stats_minutes", at + 2, node_1, 12, 22, 0, 40, 2, 18, 8, 8, 78, 5, 90, },
          { "vitals_stats_minutes", at + 3, node_1, 19, 23,  "null", "null", "null", "null", 14, 0, 0, 0, 0, },
          { "vitals_stats_minutes", at + 1, node_2, 3, 8, 1, 6, 6, 8, 15, 15, 76, 15, 105, },
          { "vitals_stats_minutes", at + 2, node_2, 4, 9, 2, 12, 7, 16, 16, 15, 85, 16, 44, },

          { "vitals_stats_seconds_2", at - 60, node_1, 3, 5, 7, 9, 8, 12, 6, 6, 74, 6, 102, },
          { "vitals_stats_seconds_2", at - 60, node_2, 2, 4, 6, 8, 4, 16, 17, 17, 99, 17, 231, },
        }

        q = [[
            insert into %s(at, node_id, l2_hit, l2_miss, plat_min, plat_max,
              ulat_min, ulat_max, requests, plat_count, plat_total, ulat_count, ulat_total)
            values(%d, '{%s}', %d, %d, %s, %s, %s, %s, %d, %d, %d, %d, %d)
        ]]

        for _, v in ipairs(test_data) do
          query = fmt(q, unpack(v))
          assert(db:query(query))
        end
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
            plat_count = 6,
            plat_total = 74,
            ulat_count = 6,
            ulat_total = 102,
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
            plat_count = 2,
            plat_total = 33,
            ulat_count = 2,
            ulat_total = 12,
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
            plat_count = 3,
            plat_total = 34,
            ulat_count = 3,
            ulat_total = 28,
          }, {
            node_id = node_1,
            at = 1509667487,
            l2_hit = 19,
            l2_miss = 23,
            requests = 14,
            plat_count = 0,
            plat_total = 0,
            ulat_count = 0,
            ulat_total = 0,
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
            plat_min = 0,
            plat_max = 20,
            ulat_min = 1,
            ulat_max = 9,
            requests = 7,
            plat_count = 7,
            plat_total = 42,
            ulat_count = 6,
            ulat_total = 34,
          }, {
            node_id = node_1,
            at = 1509667486,
            l2_hit = 12,
            l2_miss = 22,
            plat_min = 0,
            plat_max = 40,
            ulat_min = 2,
            ulat_max = 18,
            requests = 8,
            plat_count = 8,
            plat_total = 78,
            ulat_count = 5,
            ulat_total = 90,
          }, {
            node_id = node_1,
            at = 1509667487,
            l2_hit = 19,
            l2_miss = 23,
            requests = 14,
            plat_count = 0,
            plat_total = 0,
            ulat_count = 0,
            ulat_total = 0,
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
            node_id = node_1,
            at = 1509667485,
            l2_hit = 11,
            l2_miss = 21,
            plat_min = 0,
            plat_max = 20,
            ulat_min = 1,
            ulat_max = 9,
            requests = 7,
            plat_count = 7,
            plat_total = 42,
            ulat_count = 6,
            ulat_total = 34,
          }, {
            node_id = node_2,
            at = 1509667485,
            l2_hit = 3,
            l2_miss = 8,
            plat_min = 1,
            plat_max = 6,
            ulat_min = 6,
            ulat_max = 8,
            requests = 15,
            plat_count = 15,
            plat_total = 76,
            ulat_count = 15,
            ulat_total = 105,
          }, {
            node_id = node_1,
            at = 1509667486,
            l2_hit = 12,
            l2_miss = 22,
            plat_min = 0,
            plat_max = 40,
            ulat_min = 2,
            ulat_max = 18,
            requests = 8,
            plat_count = 8,
            plat_total = 78,
            ulat_count = 5,
            ulat_total = 90,
          },  {
            node_id = node_2,
            at = 1509667486,
            l2_hit = 4,
            l2_miss = 9,
            plat_min = 2,
            plat_max = 12,
            ulat_min = 7,
            ulat_max = 16,
            requests = 16,
            plat_count = 15,
            plat_total = 85,
            ulat_count = 16,
            ulat_total = 44,
          }, {
            node_id = node_1,
            at = 1509667487,
            l2_hit = 19,
            l2_miss = 23,
            requests = 14,
            plat_count = 0,
            plat_total = 0,
            ulat_count = 0,
            ulat_total = 0,
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
            plat_count = 23,
            plat_total = 173,
            ulat_count = 23,
            ulat_total = 333,
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
            plat_count = 6,
            plat_total = 43,
            ulat_count = 6,
            ulat_total = 25,
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
            plat_count = 8,
            plat_total = 74,
            ulat_count = 7,
            ulat_total = 47,
          }, {
            at = 1509667487,
            node_id = 'cluster',
            l2_hit = 19,
            l2_miss = 23,
            requests = 14,
            plat_count = 0,
            plat_total = 0,
            ulat_count = 0,
            ulat_total = 0,
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
            plat_count = 22,
            plat_total = 118,
            ulat_count = 21,
            ulat_total = 139,
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
            plat_count = 23,
            plat_total = 163,
            ulat_count = 21,
            ulat_total = 134,
          }, {
            at = 1509667487,
            node_id = 'cluster',
            l2_hit = 19,
            l2_miss = 23,
            requests = 14,
            plat_count = 0,
            plat_total = 0,
            ulat_count = 0,
            ulat_total = 0,
          }
        }

        assert.same(expected, res)
      end)

      it("takes an optional start_ts", function()
        stub(strategy, "table_names_for_select").returns({ "vitals_stats_seconds", "vitals_stats_seconds_2"})

        local res, err = strategy:select_stats("seconds", "cluster", nil, 1509667486)

        assert.is_nil(err)

        local expected = {
          {
            at = 1509667486,
            node_id = 'cluster',
            l2_hit = 12,
            l2_miss = 5,
            plat_min = 2,
            plat_max = 20,
            ulat_min = 4,
            ulat_max = 14,
            requests = 8,
            plat_count = 8,
            plat_total = 74,
            ulat_count = 7,
            ulat_total = 47,
          }, {
            at = 1509667487,
            node_id = 'cluster',
            l2_hit = 19,
            l2_miss = 23,
            plat_count = 0,
            plat_total = 0,
            requests = 14,
            ulat_count = 0,
            ulat_total = 0,
          }
        }

        assert.same(expected, res)
      end)
    end)

    describe(":select_stats() when no current table names", function()
      it("returns an empty set", function()
        stub(strategy, "table_names_for_select").returns({})
        local res, err = strategy:select_stats("seconds", "cluster")

        assert.is_nil(err)
        assert.same({}, res)
      end)
    end)

    describe(":select_phone_home", function()
      -- data starts 10 minutes ago
      local minute_start_at = time() - ( time() % 60 ) - 600
      local node_1 = strategy.node_id
      local node_2 = "8374682f-17fd-42cb-b1dc-7694d6f65ba0"

      before_each(function()
        -- node_1 data spanning three minutes
        local test_data_1 = {
          { minute_start_at, 0, 0, nil, nil, nil, nil, 0, 0, 0, 0, 0, },
          { minute_start_at + 61, 0, 3, 0, 11, 193, 212, 1, 11, 1, 11, 212, },
          { minute_start_at + 122, 3, 4, 1, 8, 60, 9182, 4, 4, 8, 4, 10000 },
        }

        -- node_2 data spanning two minutes
        local test_data_2 = {
          { minute_start_at + 61, 1, 5, 0, 99, 25, 144, 9, 9, 300, 8, 350, },
          { minute_start_at + 180, 1, 7, 0, 0, 13, 19, 8, 8, 0, 8, 97, },
        }

        assert(strategy:insert_stats(test_data_1, node_1))
        assert(strategy:insert_stats(test_data_2, node_2))

      end)

      it("returns stats for phone home", function()
        local res, err = strategy:select_phone_home()

        assert.is_nil(err)

        local expected = {{}}
        expected[1]["v.cdht"] = 3
        expected[1]["v.cdmt"] = 7
        expected[1]["v.lprn"] = 0
        expected[1]["v.lprx"] = 11
        expected[1]["v.lun"] = 60
        expected[1]["v.lux"] = 9182
        expected[1]["v.nt"] = 2
        expected[1]["v.lpra"] = 1
        expected[1]["v.lua"] = 681

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
          {now - 4000, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, },
          {now, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, },
        }

        strategy:insert_stats(data_to_insert, node_id)

        -- remove everything older than one hour
        local res, err = strategy:delete_stats({ minutes = 3600 })

        assert.same(1, res)
        assert.is_nil(err)
      end)
    end)


    describe(":insert_consumer_stats()", function()
      it("is a no-op", function()
        assert(strategy:insert_consumer_stats())
      end)
    end)


    describe(":select_consumer_stats()", function()
      local node_id = "63be463e-f75f-49fd-bf79-0d47f54ee5de"
      local service = "20426633-55dc-4050-89ef-2382c95a611e"
      local route   = "8374682f-17fd-42cb-b1dc-7694d6f65ba0"
      local cons_id = utils.uuid()
      local now     = time()
      local minute  = now - (now % 60)

      before_each(function()
        local q, query

        q = "insert into vitals_codes_by_consumer_route" ..
            "(consumer_id, service_id, route_id, code, at, duration, count) " ..
            "values('%s', '%s', '%s', '%s', to_timestamp(%d), %d, %d)"

        local data_to_insert = {
          {cons_id, service, route, "200", now - 2, 1, 1},
          {cons_id, service, route, "200", now - 1, 1, 3},
          {cons_id, service, route, "200", now, 1, 4},
          {cons_id, service, route, "200", minute - 60, 60, 19},
          {cons_id, service, route, "401", now - 1, 1, 5},
          {cons_id, service, route, "401", now, 1, 7},
          {cons_id, service, route, "401", minute - 60, 60, 20},
          {cons_id, service, route, "401", minute, 60, 24},
        }

        for _, row in ipairs(data_to_insert) do
          query = fmt(q, unpack(row))
          assert(db:query(query))
        end

        strategy:init(node_id, "testhostname")
      end)


      it("returns seconds stats for a consumer across the cluster", function()
        local opts = {
          consumer_id = cons_id,
          duration    = 1,
        }

        local results, _ = strategy:select_consumer_stats(opts)

        local expected = {
          {
            node_id = "cluster",
            at          = now - 2,
            count       = 1,
          },
          {
            node_id = "cluster",
            at          = now - 1,
            count       = 8,
          },
          {
            node_id = "cluster",
            at          = now,
            count       = 11,
          },
        }

        table.sort(results, function(a,b)
          return a.count < b.count
        end)

        assert.same(expected, results)
      end)


      it("returns minutes stats for a consumer across the cluster", function()
        local opts = {
          consumer_id = cons_id,
          duration    = 60,
        }

        local results, _ = strategy:select_consumer_stats(opts)

        local expected = {
          {
            node_id = "cluster",
            at          = minute,
            count       = 24,
          },
          {
            node_id = "cluster",
            at          = minute - 60,
            count       = 39,
          },
        }

        table.sort(results, function(a,b)
          return a.count < b.count
        end)

        assert.same(expected, results)
      end)


      it("takes an optional start_ts", function()
        local opts = {
          consumer_id = cons_id,
          duration    = 60,
          start_ts    = minute,
        }

        local results, _ = strategy:select_consumer_stats(opts)

        local expected = {
          {
            node_id = "cluster",
            at          = minute,
            count       = 24,
          },
        }

        assert.same(expected, results)
      end)
    end)


    describe(":insert_status_code_classes", function()
      it("calls insert_status_codes with the right args", function()
        stub(pg_strategy, "insert_status_codes")

        local data = {}

        local opts = {
          entity_type = "cluster",
        }

        strategy:insert_status_code_classes(data)
        assert.stub(pg_strategy.insert_status_codes).was_called_with(strategy, data, opts)
      end)
    end)


    describe(":insert_status_code_classes_by_workspace", function()
      it("calls insert_status_codes with the right args", function()
        stub(pg_strategy, "insert_status_codes")

        local data = {}

        local opts = {
          entity_type = "workspace",
        }

        strategy:insert_status_code_classes_by_workspace(data)
        assert.stub(pg_strategy.insert_status_codes).was_called_with(strategy, data, opts)
      end)
    end)


    describe(":insert_status_codes_by_route", function()
      it("calls insert_status_codes with the right args", function()
        stub(pg_strategy, "insert_status_codes")

        local data = {}

        local opts = {
          entity_type = "route",
        }

        strategy:insert_status_codes_by_route(data)
        assert.stub(pg_strategy.insert_status_codes).was_called_with(strategy, data, opts)
      end)
    end)


    describe(":insert_status_codes_by_consumer_and_route", function()
      it("calls insert_status_codes with the right args", function()
        stub(pg_strategy, "insert_status_codes")

        local data = {}

        local opts = {
          entity_type = "consumer_route",
        }

        strategy:insert_status_codes_by_consumer_and_route(data)
        assert.stub(pg_strategy.insert_status_codes).was_called_with(strategy, data, opts)
      end)
    end)


    describe(":insert_status_codes", function()

      it("inserts into vitals_codes_by_route", function()
        local route_id = utils.uuid()
        local service_id = utils.uuid()

        local now    = ngx.time()
        local minute = now - (now % 60)

        local data = {
          { route_id, service_id, "404", tostring(now), "1", 4 },
          { route_id, service_id, "404", tostring(now - 1), "1", 2 },
          { route_id, service_id, "500", tostring(minute), "60", 5 },
        }

        local opts = {
          entity_type = "route",
        }

        assert(strategy:insert_status_codes(data, opts))

        local q = [[
          select service_id, route_id, code, extract('epoch' from at) as at,
            duration, count
          from vitals_codes_by_route
          order by count
        ]]

        local results = db:query(q)

        local expected = {
          {
            at         = now - 1,
            code       = 404,
            count      = 2,
            duration   = 1,
            service_id = service_id,
            route_id   = route_id,
          },
          {
            at         = now,
            code       = 404,
            count      = 4,
            duration   = 1,
            service_id = service_id,
            route_id   = route_id,
          },
          {
            at         = minute,
            code       = 500,
            count      = 5,
            duration   = 60,
            service_id = service_id,
            route_id   = route_id,
          },
        }

        assert.same(expected, results)
      end)

      it("inserts into vitals_codes_by_consumer_route", function()
        local consumer_id = utils.uuid()
        local route_id = utils.uuid()
        local service_id = utils.uuid()

        local now    = ngx.time()
        local minute = now - (now % 60)

        local data = {
          { consumer_id, route_id, service_id, "404", tostring(now), "1", 4 },
          { consumer_id, route_id, service_id, "404", tostring(now - 1), "1", 2 },
          { consumer_id, route_id, service_id, "500", tostring(minute), "60", 5 },
        }

        local opts = {
          entity_type = "consumer_route",
        }

        assert(strategy:insert_status_codes(data, opts))

        local q = [[
          select consumer_id, service_id, route_id, code,
            extract('epoch' from at) as at, duration, count
          from vitals_codes_by_consumer_route
          order by count
        ]]

        local results = db:query(q)

        local expected = {
          {
            at         = now - 1,
            code       = 404,
            count      = 2,
            duration   = 1,
            service_id = service_id,
            route_id   = route_id,
            consumer_id = consumer_id,
          },
          {
            at         = now,
            code       = 404,
            count      = 4,
            duration   = 1,
            service_id = service_id,
            route_id   = route_id,
            consumer_id = consumer_id,
          },
          {
            at         = minute,
            code       = 500,
            count      = 5,
            duration   = 60,
            service_id = service_id,
            route_id   = route_id,
            consumer_id = consumer_id,
          },
        }

        assert.same(expected, results)
      end)

      it ("inserts into vitals_code_classes_by_cluster", function()
        local uuid = utils.uuid()

        assert(strategy:init(uuid, "testhostname"))

        local now = ngx.time()
        local minute = now - (now % 60)

        local data = {
          { 1, now, 1, 4 },
          { 2, now, 1, 1 },
          { 2, now - 1, 1, 2 },
          { 2, minute, 60, 3 },
        }

        local opts = {
          entity_type = "cluster",
        }

        assert(strategy:insert_status_codes(data, opts))

        -- force a sort order to make assertion easier
        local q = [[
          select code_class, extract('epoch' from at) as at,
            duration, count from vitals_code_classes_by_cluster
              order by count
        ]]

        local results = db:query(q)

        local expected = {
          {
            at         = now,
            code_class = 2,
            count      = 1,
            duration   = 1,
          },
          {
            at         = now - 1,
            code_class = 2,
            count      = 2,
            duration   = 1,
          },
          {
            at         = minute,
            code_class = 2,
            count      = 3,
            duration   = 60,
          },
          {
            at         = now,
            code_class = 1,
            count      = 4,
            duration   = 1,
          },
        }

        assert.same(expected, results)
      end)

      it ("inserts into vitals_code_classes_by_workspace", function()
        local node_id = utils.uuid()
        local workspace_id = utils.uuid()

        assert(strategy:init(node_id, "testhostname"))

        local now = ngx.time()
        local minute = now - (now % 60)

        local data = {
          { workspace_id, 1, now, 1, 4 },
          { workspace_id, 2, now, 1, 1 },
          { workspace_id, 2, now - 1, 1, 2 },
          { workspace_id, 2, minute, 60, 3 },
        }

        local opts = {
          entity_type = "workspace",
        }

        assert(strategy:insert_status_codes(data, opts))

        -- force a sort order to make assertion easier
        local q = [[
          select workspace_id, code_class, extract('epoch' from at) as at,
            duration, count from vitals_code_classes_by_workspace
              order by count
        ]]

        local results = db:query(q)

        local expected = {
          {
            at         = now,
            code_class = 2,
            count      = 1,
            duration   = 1,
            workspace_id = workspace_id,
          },
          {
            at         = now - 1,
            code_class = 2,
            count      = 2,
            duration   = 1,
            workspace_id = workspace_id,
          },
          {
            at         = minute,
            code_class = 2,
            count      = 3,
            duration   = 60,
            workspace_id = workspace_id,
          },
          {
            at         = now,
            code_class = 1,
            count      = 4,
            duration   = 1,
            workspace_id = workspace_id,
          },
        }

        assert.same(expected, results)
      end)
    end)


    describe(":select_status_codes (cluster)", function()
      -- data starts a couple minutes ago
      local start_at = time() - 90
      local start_minute = start_at - (start_at % 60)

      before_each(function()
        local test_data = {
          {4, start_at,      1, 1},
          {4, start_at + 1,  1, 3},
          {4, start_minute, 60, 4},
          {4, start_at + 60, 1, 7},
          {4, start_minute + 60, 60, 7},
          {5, start_at + 2,  1, 2},
          {5, start_minute, 60, 2},
          {5, start_at + 60, 1, 5},
          {5, start_at + 61, 1, 6},
          {5, start_at + 62, 1, 8},
          {5, start_minute + 60, 60, 19},
        }

        local q, query

        q = "insert into vitals_code_classes_by_cluster(code_class, at, duration, count) " ..
          "values('%s', to_timestamp(%d), %d, %d)"

        for _, row in ipairs(test_data) do
          query = fmt(q, unpack(row))
          assert(db:query(query))
        end
      end)

      after_each(function()
        db:query("TRUNCATE vitals_code_classes_by_cluster")
      end)

      it("returns seconds counts across the cluster", function()
        local opts = {
          duration    = 1,
          entity_type = "cluster",
        }

        local results, err = strategy:select_status_codes(opts)
        assert.is_nil(err)

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
          entity_type = "cluster",
        }

        local results, _ = strategy:select_status_codes(opts)

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


      it("takes an optional start_ts", function()
        local opts = {
          duration    = 60,
          level       = "cluster",
          entity_type = "cluster",
          start_ts    = start_minute + 39,
        }

        local results, _ = strategy:select_status_codes(opts)

        local expected = {
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


    describe(":select_status_codes (workspace)", function()
      local workspace_id = utils.uuid()
      local workspace_id_2 = utils.uuid()

      -- data starts a couple minutes ago
      local start_at = time() - 90
      local start_minute = start_at - (start_at % 60)

      before_each(function()
        local test_data = {
          {workspace_id, 4, start_at,      1, 1},
          {workspace_id, 4, start_at + 1,  1, 3},
          {workspace_id, 4, start_minute, 60, 4},
          {workspace_id, 4, start_at + 60, 1, 7},
          {workspace_id, 4, start_minute + 60, 60, 7},
          {workspace_id, 5, start_at + 2,  1, 2},
          {workspace_id, 5, start_minute, 60, 2},
          {workspace_id, 5, start_at + 60, 1, 5},
          {workspace_id, 5, start_at + 61, 1, 6},
          {workspace_id, 5, start_at + 62, 1, 8},
          {workspace_id, 5, start_minute + 60, 60, 19},
          {workspace_id_2, 4, start_minute + 60, 60, 99},
          {workspace_id_2, 5, start_at + 2,  1, 99},
        }

        local q = "insert into vitals_code_classes_by_workspace" ..
            "(workspace_id, code_class, at, duration, count) " ..
            "values('%s', '%s', to_timestamp(%d), %d, %d)"

        for _, row in ipairs(test_data) do
          assert(db:query(fmt(q, unpack(row))))
        end
      end)

      after_each(function()
        db:query("TRUNCATE vitals_code_classes_by_workspace")
      end)

      it("returns seconds counts across the workspace", function()
        local opts = {
          duration    = 1,
          entity_type = "workspace",
          entity_id   = workspace_id,
        }

        local results, err = strategy:select_status_codes(opts)
        assert.is_nil(err)

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


      it("returns minutes counts across the workspace", function()
        local opts = {
          duration    = 60,
          level       = "cluster",
          entity_type = "workspace",
          entity_id   = workspace_id,
        }

        local results, _ = strategy:select_status_codes(opts)

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


      it("takes an optional start_ts", function()
        local opts = {
          duration    = 60,
          level       = "cluster",
          entity_type = "workspace",
          entity_id   = workspace_id,
          start_ts    = start_minute + 39,
        }

        local results, _ = strategy:select_status_codes(opts)

        local expected = {
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


    describe(":select_status_codes (service)", function()
      local uuid   = utils.uuid()
      local uuid_2 = utils.uuid()
      local route  = utils.uuid()
      local route_2 = utils.uuid()

      assert(strategy:init(uuid, "testhostname"))

      local now    = time()
      local minute = now - (now % 60)

      before_each(function()
        local service_data = {
          { route, uuid, 404, now, 1, 4 },
          { route_2, uuid_2, 404, now, 1, 6 },
          { route, uuid, 404, now - 1, 1, 2 },
          { route, uuid, 500, minute, 60, 3 },
          { route_2, uuid_2, 500, minute, 60, 5 },
        }

        local q = [[
          insert into vitals_codes_by_route(route_id, service_id, code, at, duration, count)
          values('%s', '%s', '%s', to_timestamp(%d), %d, %d)
        ]]

        for _, v in ipairs(service_data) do
          assert(db:query(fmt(q, unpack(v))))
        end
      end)

      it("returns codes by service (seconds)", function()
        local opts = {
          duration   = 1,
          entity_id = uuid,
          entity_type = "service",
        }

        local results, err = strategy:select_status_codes(opts)
        assert.is_nil(err)

        local expected = {
          {
            at         = now - 1,
            code       = 404,
            count      = 2,
            service_id = uuid,
          },
          {
            at         = now,
            code       = 404,
            count      = 4,
            service_id = uuid,
          },
        }

        table.sort(results, function(a,b)
          return a.count < b.count
        end)

        assert.same(expected, results)
      end)


      it("returns codes by service (minutes)", function()
        local opts = {
          duration   = 60,
          entity_id = uuid_2,
          entity_type = "service",
        }

        local results, err = strategy:select_status_codes(opts)

        assert.is_nil(err)

        local expected = {
          {
            at         = minute,
            code       = 500,
            count      = 5,
            service_id = uuid_2,
          },
        }

        assert.same(expected, results)
      end)
    end)


    describe(":select_status_codes (route)", function()
      local uuid   = utils.uuid()
      local uuid_2 = utils.uuid()

      assert(strategy:init(uuid, "testhostname"))

      local now    = time()
      local minute = now - (now % 60)

      before_each(function()
        local service_id = utils.uuid()

        local route_data = {
          { uuid, service_id, 404, now, 1, 4 },
          { uuid_2, service_id, 404, now, 1, 6 },
          { uuid, service_id, 404, now - 1, 1, 2 },
          { uuid, service_id, 500, minute, 60, 3 },
          { uuid_2, service_id, 500, minute, 60, 5 },
        }

        local q = [[
          insert into vitals_codes_by_route(route_id, service_id, code, at, duration, count)
          values('%s', '%s', '%s', to_timestamp(%d), %d, %d)
        ]]

        for _, v in ipairs(route_data) do
          assert(db:query(fmt(q, unpack(v))))
        end

      end)

      it("returns codes by route (seconds)", function()
        local opts = {
          duration   = 1,
          entity_id = uuid,
          entity_type = "route",
        }

        local results, err = strategy:select_status_codes(opts)
        assert.is_nil(err)

        local expected = {
          {
            at         = now - 1,
            code       = 404,
            count      = 2,
            route_id   = uuid,
          },
          {
            at         = now,
            code       = 404,
            count      = 4,
            route_id   = uuid,
          },
        }

        table.sort(results, function(a,b)
          return a.count < b.count
        end)

        assert.same(expected, results)
      end)


      it("returns codes by route (minutes)", function()
        local opts = {
          duration   = 60,
          entity_id = uuid_2,
          entity_type = "route",
        }

        local results, err = strategy:select_status_codes(opts)

        assert.is_nil(err)

        local expected = {
          {
            at         = minute,
            code       = 500,
            count      = 5,
            route_id   = uuid_2,
          },
        }

        assert.same(expected, results)
      end)
    end)


    describe(":select_status_codes (consumer)", function()
      local uuid   = utils.uuid()
      local uuid_2 = utils.uuid()
      local route_1 = utils.uuid()
      local route_2 = utils.uuid()
      local service_id = utils.uuid()

      assert(strategy:init(uuid, "testhostname"))

      local now    = time()
      local minute = now - (now % 60)

      before_each(function()
        local route_data = {
          { uuid, route_1, service_id, 404, now, 1, 4 },
          { uuid_2, route_1, service_id, 404, now, 1, 6 },
          { uuid, route_1, service_id, 404, now - 1, 1, 2 },
          { uuid, route_1, service_id, 500, minute, 60, 3 },
          { uuid_2, route_1, service_id, 404, minute, 60, 5 },
          { uuid_2, route_1, service_id, 500, minute, 60, 7 },
          { uuid_2, route_2, service_id, 404, minute, 60, 1 },
        }

        local q = [[
          insert into vitals_codes_by_consumer_route(consumer_id, route_id,
          service_id, code, at, duration, count)
          values('%s', '%s', '%s', '%s', to_timestamp(%d), %d, %d)
        ]]

        for _, v in ipairs(route_data) do
          assert(db:query(fmt(q, unpack(v))))
        end
      end)

      it("returns codes by consumer (seconds)", function()
        local opts = {
          duration   = 1,
          entity_id = uuid,
          entity_type = "consumer",
        }

        local results, err = strategy:select_status_codes(opts)
        assert.is_nil(err)

        local expected = {
          {
            at          = now - 1,
            code        = 404,
            count       = 2,
            consumer_id = uuid,
          },
          {
            at          = now,
            code        = 404,
            count       = 4,
            consumer_id = uuid,
          },
        }

        table.sort(results, function(a,b)
          return a.count < b.count
        end)

        assert.same(expected, results)
      end)

      it("returns codes by consumer (minutes)", function()
        local opts = {
          duration   = 60,
          entity_id = uuid_2,
          entity_type = "consumer",
        }

        local results, err = strategy:select_status_codes(opts)
        assert.is_nil(err)

        local expected = {
          {
            at          = minute,
            code        = 404,
            count       = 6,
            consumer_id = uuid_2,
          },
          {
            at          = minute,
            code        = 500,
            count       = 7,
            consumer_id = uuid_2,
          },
        }

        table.sort(results, function(a,b)
          return a.count < b.count
        end)

        assert.same(expected, results)
      end)

      it("returns codes for a consumer and all routes", function()
        local opts = {
          duration   = 60,
          entity_id = uuid_2,
          entity_type = "consumer_route",
        }

        local results, err = strategy:select_status_codes(opts)
        assert.is_nil(err)

        local expected = {
          {
            at          = minute,
            code        = 404,
            count       = 1,
            consumer_id = uuid_2,
            route_id    = route_2,
          },
          {
            at          = minute,
            code        = 404,
            count       = 5,
            consumer_id = uuid_2,
            route_id    = route_1,
          },
          {
            at          = minute,
            code        = 500,
            count       = 7,
            consumer_id = uuid_2,
            route_id    = route_1,
          },
        }

        table.sort(results, function(a,b)
          return a.count < b.count
        end)

        assert.same(expected, results)
      end)
    end)


    describe(":select_status_codes_by_service", function()
      it("calls select_status_codes with the right arguments", function()
        stub(pg_strategy, "select_status_codes")

        local service_id = utils.uuid()

        local function_opts = {
          entity_type = "service",
          service_id = service_id,
          route_id = "foo",
          duration = "seconds",
          level = "cluster",
        }

        local query_opts = {
          entity_type = "service",
          service_id = service_id,
          route_id = "foo",
          duration = "seconds",
          level = "cluster",
          entity_id = service_id,
        }

        strategy:select_status_codes_by_service(function_opts)
        assert.stub(pg_strategy.select_status_codes).was_called_with(strategy, query_opts)
      end)
    end)


    describe(":select_status_codes_by_route", function()
      it("calls select_status_codes with the right arguments", function()
        stub(pg_strategy, "select_status_codes")

        local route_id = utils.uuid()

        local function_opts = {
          entity_type = "route",
          service_id = "foo",
          route_id = route_id,
          duration = "seconds",
          level = "cluster",
        }

        local query_opts = {
          entity_type = "route",
          service_id = "foo",
          route_id = route_id,
          duration = "seconds",
          level = "cluster",
          entity_id = route_id,
        }

        strategy:select_status_codes_by_route(function_opts)
        assert.stub(pg_strategy.select_status_codes).was_called_with(strategy, query_opts)
      end)
    end)


    describe(":select_status_codes_by_consumer", function()
      it("calls select_status_codes with the right arguments", function()
        stub(pg_strategy, "select_status_codes")

        local consumer_id = utils.uuid()

        local function_opts = {
          entity_type = "consumer",
          service_id = "foo",
          route_id = "bar",
          consumer_id = consumer_id,
          duration = "seconds",
          level = "cluster",
        }

        local query_opts = {
          entity_type = "consumer",
          service_id = "foo",
          route_id = "bar",
          consumer_id = consumer_id,
          duration = "seconds",
          level = "cluster",
          entity_id = consumer_id,
        }

        strategy:select_status_codes_by_consumer(function_opts)
        assert.stub(pg_strategy.select_status_codes).was_called_with(strategy, query_opts)
      end)
    end)


    describe(":delete_status_codes", function()
      local uuid   = utils.uuid()
      local uuid_2 = utils.uuid()

      before_each(function()
        db:query("TRUNCATE vitals_codes_by_route")
        db:query("TRUNCATE vitals_code_classes_by_cluster")
        db:query("TRUNCATE vitals_code_classes_by_workspace")
      end)

      it("cleans up vitals_codes_by_route", function()
        local service_id = utils.uuid()
        local data = {
          { uuid, service_id, 404, 1510560000, 1, 1 },
          { uuid_2, service_id, 404, 1510560001, 1, 5 },
          { uuid, service_id, 404, 1510560002, 1, 4 },
          { uuid, service_id, 404, 1510560000, 60, 19 },
          { uuid_2, service_id, 404, 1510560000, 60, 14 },
          { uuid, service_id, 500, 1510560001, 1, 5 },
          { uuid_2, service_id, 500, 1510560002, 1, 8 },
          { uuid, service_id, 500, 1510560000, 60, 20 },
          { uuid, service_id, 500, 1510560060, 60, 24 },
        }

        local q = [[
          insert into vitals_codes_by_route(route_id, service_id, code, at,
          duration, count) values('%s', '%s', %s, to_timestamp(%d), %d, %d)
         ]]

        for _, v in ipairs(data) do
          assert(db:query(fmt(q, unpack(v))))
        end

        local opts = {
          entity_type = "route",
          minutes = 1510560001,
          seconds = 1510560002,
        }

        local res, err = strategy:delete_status_codes(opts)

        assert.is_nil(err)
        assert.same(6, res)


        local res = db:query("select count(*) from vitals_codes_by_route")
        assert.same(3, res[1].count)
      end)

      it("cleans up vitals_code_classes_by_cluster", function()
        local q, query

        q = "insert into vitals_code_classes_by_cluster(code_class, at, duration, count) " ..
          "values('%s', to_timestamp(%d), %d, %d)"

        local test_data = {
          {4, 1510560000, 1, 1},
          {4, 1510560001, 1, 3},
          {4, 1510560002, 1, 4},
          {4, 1510560000, 60, 19},
          {5, 1510560001, 1, 5},
          {5, 1510560002, 1, 7},
          {5, 1510560000, 60, 20},
          {5, 1510560060, 60, 24},
        }

        for _, row in ipairs(test_data) do
          query = fmt(q, unpack(row))
          assert(db:query(query))
        end

        local opts = {
          entity_type = "cluster",
          minutes = 1510560001,
          seconds = 1510560002,
        }

        local res, err = strategy:delete_status_codes(opts)

        assert.is_nil(err)
        assert.same(5, res)
      end)

      it("cleans up vitals_code_classes_by_workspace", function()
        local q, query

        q = "insert into vitals_code_classes_by_workspace(workspace_id, code_class, at, duration, count) " ..
          "values('%s', '%s', to_timestamp(%d), %d, %d)"

        local workspace_id = utils.uuid()

        local test_data = {
          {workspace_id, 4, 1510560000, 1, 1},
          {workspace_id, 4, 1510560001, 1, 3},
          {workspace_id, 4, 1510560002, 1, 4},
          {workspace_id, 4, 1510560000, 60, 19},
          {workspace_id, 5, 1510560001, 1, 5},
          {workspace_id, 5, 1510560002, 1, 7},
          {workspace_id, 5, 1510560000, 60, 20},
          {workspace_id, 5, 1510560060, 60, 24},
        }

        for _, row in ipairs(test_data) do
          query = fmt(q, unpack(row))
          assert(db:query(query))
        end

        local opts = {
          entity_type = "workspace",
          minutes = 1510560001,
          seconds = 1510560002,
        }

        local res, err = strategy:delete_status_codes(opts)

        assert.is_nil(err)
        assert.same(5, res)

        res, err = db:query("select count(*) from vitals_code_classes_by_workspace")

        assert.is_nil(err)
        assert.same(3, res[1].count)
      end)

      it("validates parameters", function()
        local _, err = strategy:delete_status_codes("foo")
        assert.same("opts must be a table", err)

        _, err = strategy:delete_status_codes({ entity_type = "foo", seconds = 999, minutes = 999 })
        assert.same("unknown entity_type: foo", err)

        _, err = strategy:delete_status_codes({ entity_type = "route", seconds = "foo" })
        assert.same("opts.seconds must be a number", err)

        _, err = strategy:delete_status_codes({ entity_type = "route", seconds = 999, minutes = "foo" })
        assert.same("opts.minutes must be a number", err)
      end)

      it("returns an error message when it fails", function()
        stub(strategy.db, "query").returns(nil, "failure!")

        local opts = {
          entity_type = "route",
          minutes = 1510560001,
          seconds = 1510560002,
        }

        local _, err = strategy:delete_status_codes(opts)

        assert.same("failed to delete codes. err: failure!", err)
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

        local q = "insert into vitals_node_meta(node_id, hostname) " ..
                  "values('%s', '%s')"

        for _, row in ipairs(data_to_insert) do
          local query = fmt(q, unpack(row))
          assert(dao.db:query(query))
        end

        local node_ids = { node_id, node_id_2 }

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

        local res, _ = strategy:select_node_meta(node_ids)

        assert.same(expected, res)
      end)

      it("returns an empty table when no node ids are passed in", function()
        local res, _ = strategy:select_node_meta({})

        assert.same({}, res)
      end)
    end)


    describe(":interval_width", function()
      it("returns the right size, in seconds", function()
        local width = strategy:interval_width("seconds")
        assert.same(1, width)

        width = strategy:interval_width("minutes")
        assert.same(60, width)
      end)

      it("returns nil if requested interval is unknown", function()
        local width, err = strategy:interval_width("foo")
        assert.is_nil(width)
        assert.same("interval must be 'seconds' or 'minutes'", err)
      end)
    end)
  end)
end)
