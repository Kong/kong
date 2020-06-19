local cassandra_strategy = require "kong.tools.public.rate-limiting.strategies.cassandra"
local helpers        = require "spec.helpers"
local DB                 = require "kong.db"

local function window_floor(size, time)
  return math.floor(time / size) * size
end

do
  local say      = require "say"
  local luassert = require "luassert"

  local function has(state, args)
    local fixture, t = args[1], args[2]
    local has

    for i = 1, #t do
      local ok = pcall(assert.same, fixture, t[i])
      if ok then
        has = true
        break
      end
    end

    return has
  end

  say:set("assertion.has.positive",
          "Expected array to hold value but it did not\n" ..
          "Expected to have:\n%s\n"                       ..
          "But contained only:\n%s")
  say:set("assertion.has.negative",
          "Expected array to not hold value but it did\n" ..
          "Expected to not have:\n%s\n"                   ..
          "But array was:\n%s")
  luassert:register("assertion", "has", has,
                    "assertion.has.positive",
                    "assertion.has.negative")
end

for _, strategy in helpers.each_strategy() do

if strategy == "postgres" then
  return
end

describe("rate-limiting: Cassadra strategy", function()
  local strategy
  local cluster

  setup(function()
    local db = assert(DB.new(helpers.test_conf, strategy))
    assert(db:init_connector())

    strategy = cassandra_strategy.new(db)
    cluster  = db.connector.cluster
  end)

  teardown(function()
    cluster:execute("TRUNCATE rl_counters")
  end)

  local diffs = {
    {
      key     = "foo",
      windows = {
        {
          namespace = "my_namespace",
          window    = 1502496000,
          size      = 10,
          diff      = 5,
        },
        {
          namespace = "my_namespace",
          window    = 1502496000,
          size      = 5,
          diff      = 2,
        },
      }
    },
    {
      key     = "1.2.3.4",
      windows = {
        {
          namespace = "my_namespace",
          window    = 1502496000,
          size      = 10,
          diff      = 5,
        },
        {
          namespace = "my_namespace",
          window    = 1502496000,
          size      = 5,
          diff      = 1,
        },
      }
    },
  }

  local expected_rows = {
    {
      count        = 5,
      key          = "1.2.3.4",
      namespace    = "my_namespace",
      window_size  = 10,
      window_start = 1502496000,
    },
    {
      count        = 5,
      key          = "foo",
      namespace    = "my_namespace",
      window_size  = 10,
      window_start = 1502496000,
    },
    {
      count        = 1,
      key          = "1.2.3.4",
      namespace    = "my_namespace",
      window_size  = 5,
      window_start = 1502496000,
    },
    {
      count        = 2,
      key          = "foo",
      namespace    = "my_namespace",
      window_size  = 5,
      window_start = 1502496000,
    },
    meta = {
      has_more_pages = false
    },
    type = "ROWS",
  }

  describe(":push_diffs()", function()
    it("pushes a diffs structure to the counters column_family", function()

      -- no return values
      strategy:push_diffs(diffs)

      -- check
      local rows = assert(cluster:execute("SELECT * FROM rl_counters"))
      assert.same(expected_rows, rows)
    end)
  end)

  describe(":get_window()", function()
    it("retrieves the counter for a given window", function()
      local count = assert(strategy:get_window("1.2.3.4", "my_namespace", 1502496000, 5))
      assert.equal(1, count)

      count = assert(strategy:get_window("1.2.3.4", "my_namespace", 1502496000, 10))
      assert.equal(5, count)

      count = assert(strategy:get_window("foo", "my_namespace", 1502496000, 5))
      assert.equal(2, count)

      count = assert(strategy:get_window("foo", "my_namespace", 1502496000, 10))
      assert.equal(5, count)
    end)
  end)

  describe(":get_counters()", function()
    local MIDNIGHT = 684288000

    local fixture_windows = {
      {
        key     = "1.2.3.4",
        windows = {
          {
            namespace = "namespace_1",
            window    = MIDNIGHT - 5,
            size      = 5,
            diff      = 1,
          },
          {
            namespace = "namespace_1",
            window    = MIDNIGHT,
            size      = 5,
            diff      = 1,
          },
          {
            namespace = "namespace_2",
            window    = MIDNIGHT,
            size      = 5,
            diff      = 1,
          }
        },
      },
    }

    setup(function()
      strategy:push_diffs(fixture_windows)
    end)

    it("yields all counters from windows inside a namespace", function()
      local counters = {}
      for row in strategy:get_counters("namespace_1", { 5, 10 }, MIDNIGHT) do
        table.insert(counters, row)
      end
      assert.equal(2, #counters)

      counters = {}
      for row in strategy:get_counters("namespace_2", { 5, 10 }, MIDNIGHT) do
        table.insert(counters, row)
      end
      assert.equal(1, #counters)
    end)

    it("yields counters from the current and previous windows", function()
      local counters = {}
      for row in strategy:get_counters("namespace_1", { 5 }, MIDNIGHT + 1) do
        table.insert(counters, row)
      end
      assert.equal(2, #counters)
      assert.has({
        key          = "1.2.3.4",
        namespace    = "namespace_1",
        window_size  = 5,
        window_start = MIDNIGHT,
        count        = 1
      }, counters)
      assert.has({
        key          = "1.2.3.4",
        namespace    = "namespace_1",
        window_size  = 5,
        window_start = MIDNIGHT - 5,
        count        = 1
      }, counters)
    end)
  end)

  describe(":purge() helpers", function()
    describe(".get_window_start_lists", function()
      it("returns correct number of results", function()
        local sizes = {8, 10, 20, 50, 100, 200, 400, 800}
        local starts_per_size = strategy.get_window_start_lists(sizes, 1513788040)

        local n = 0
        for size, starts in pairs(starts_per_size) do
          -- correct number of window starts for a given window size
          assert.same(math.floor(3600/size), #starts)
          n = n + 1
        end

        -- correct number of window start lists
        assert.same(#sizes, n)
      end)

      it("returns correct window start values", function()
        local sizes = {200, 400, 800}
        local mock_time = 1513788040
        local starts = strategy.get_window_start_lists(sizes, mock_time)

        for size, start in pairs(starts) do
          -- last obsolete window start
          local last_window_start = window_floor(size, mock_time) - 2 * size
          for _, start in ipairs(start) do
            assert.same(last_window_start, start.val)
            last_window_start = last_window_start - size
          end
        end
      end)
    end)
  end)

  describe(":purge()", function()
    local mock_start_1 = ngx.time()
    local mock_start_2 = window_floor(2, ngx.time())

    local new_diffs = {
      {
        key     = "foo",
        windows = {
          {
            namespace = "my_namespace",
            window    = mock_start_1,
            size      = 1,
            diff      = 5,
          },
          {
            namespace = "my_namespace",
            window    = mock_start_1,
            size      = 1,
            diff      = 2,
          },
          {
            namespace = "my_namespace",
            window    = mock_start_2,
            size      = 2,
            diff      = 2,
          },
        }
      }
    }
    local new_expected_rows = {
      {
        count        = 2,
        key          = "foo",
        namespace    = "my_namespace",
        window_size  = 2,
        window_start = mock_start_2,
      },
      {
        count        = 7,
        key          = "foo",
        namespace    = "my_namespace",
        window_size  = 1,
        window_start = mock_start_1,
      },
      meta = {
        has_more_pages = false
      },
      type = "ROWS",
    }

    cluster:execute("TRUNCATE rl_counters")
    strategy:push_diffs(new_diffs)

    it("should not purge valid counters", function()
      strategy:purge("my_namespace", {1, 2}, ngx.time())
      local rows = assert(cluster:execute("SELECT * FROM rl_counters"))
      table.sort(rows, function(r1, r2) return r1.count < r2.count end)
      assert.same(new_expected_rows, rows)
    end)

    it("should purge some expired counters", function()
      local expected_rows = {
        {
          count        = 2,
          key          = "foo",
          namespace    = "my_namespace",
          window_size  = 2,
          window_start = mock_start_2,
        },
        meta = {
          has_more_pages = false
        },
        type = "ROWS",
      }

      strategy:purge("my_namespace", {1}, ngx.time() + 20)
      local rows = assert(cluster:execute("SELECT * FROM rl_counters"))
      assert.equal(1, #rows)
      assert.same(expected_rows, rows)
    end)

    it("should purge all counters", function()
      strategy:purge("my_namespace", {2}, ngx.time() + 20)
      local rows = assert(cluster:execute("SELECT * FROM rl_counters"))
      assert.equal(0, #rows)
    end)
  end)
end)
end
