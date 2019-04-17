local postgres_strategy = require "kong.tools.public.rate-limiting.strategies.postgres"
local helpers       = require "spec.helpers"
local DB                = require "kong.db"

local function window_floor(size, time)
  return math.floor(time / size) * size
end

for _, strategy in helpers.each_strategy() do

  if strategy == "cassandra" then
    return
  end

  describe("rate-limiting: Postgres strategy", function()
    local strategy
    local db

    local mock_time = ngx.time()
    local mock_window_size = 60

    local mock_start = window_floor(mock_window_size, mock_time)
    local mock_prev_start = window_floor(mock_window_size, mock_time) -
                            mock_window_size

    setup(function()
      db = assert(DB.new(helpers.test_conf))
      assert(db:init_connector())

      strategy = postgres_strategy.new(db)
      db       = db.connector

      db:query("TRUNCATE rl_counters")
    end)

    teardown(function()
      db:query("TRUNCATE rl_counters")
    end)

    local diffs = {
      {
        key     = "foo",
        windows = {
          {
            namespace = "my_namespace",
            window    = mock_start,
            size      = mock_window_size,
            diff      = 5,
          },
          {
            namespace = "my_namespace",
            window    = mock_prev_start,
            size      = mock_window_size,
            diff      = 2,
          },
        }
      },
      {
        key     = "1.2.3.4",
        windows = {
          {
            namespace = "my_namespace",
            window    = mock_start,
            size      = mock_window_size,
            diff      = 5,
          },
          {
            namespace = "my_namespace",
            window    = mock_prev_start,
            size      = mock_window_size,
            diff      = 1,
          },
        }
      },
    }

    local new_diffs = {
      {
        key     = "foo",
        windows = {
          {
            namespace = "my_namespace",
            window    = mock_start,
            size      = mock_window_size,
            diff      = 5,
          },
        }
      },
      {
        key     = "1.2.3.4",
        windows = {
          {
            namespace = "my_namespace",
            window    = mock_start,
            size      = mock_window_size,
            diff      = 5,
          },
        }
      },
    }

    local expected_rows = {
      {
        count        = 2,
        key          = "foo",
        namespace    = "my_namespace",
        window_size  = mock_window_size,
        window_start = mock_prev_start,
      },
      {
        count        = 1,
        key          = "1.2.3.4",
        namespace    = "my_namespace",
        window_size  = mock_window_size,
        window_start = mock_prev_start,
      },
      {
        count        = 10,
        key          = "foo",
        namespace    = "my_namespace",
        window_size  = mock_window_size,
        window_start = mock_start,
      },
      {
        count        = 10,
        key          = "1.2.3.4",
        namespace    = "my_namespace",
        window_size  = mock_window_size,
        window_start = mock_start,
      },
    }

    describe(":push_diffs()", function()
      it("pushes a diffs structure to the counters column_family", function()

        -- no return values
        strategy:push_diffs(diffs)

        -- push diffs with existing values in postgres
        strategy:push_diffs(new_diffs)

        -- check
        local rows = assert(db:query("SELECT * FROM rl_counters"))
        assert.same(expected_rows, rows)
      end)
    end)

    describe(":get_window()", function()
      it("retrieves the counter for a given window", function()
        local count = assert(strategy:get_window("1.2.3.4", "my_namespace",
                                                 mock_start, mock_window_size))
        assert.equal(10, count)

        count = assert(strategy:get_window("1.2.3.4", "my_namespace",
                                           mock_prev_start, mock_window_size))
        assert.equal(1, count)

        count = assert(strategy:get_window("foo", "my_namespace", mock_start,
                                           mock_window_size))
        assert.equal(10, count)

        count = assert(strategy:get_window("foo", "my_namespace", mock_prev_start,
                                           mock_window_size))
        assert.equal(2, count)
      end)
    end)

    describe(":get_counters", function()
      -- setup our extra rows to simulate old entries
      setup(function()
        db:query(
  [[INSERT INTO rl_counters (key, namespace, window_start, window_size, count)
    VALUES("1.2.3.4", "my_namespace", ]] .. mock_start - 3 * mock_window_size ..
  [[, ]] .. mock_window_size .. [[, 9)]]
      )
      end)

      it("iterates over each window for each key", function()
        local i = 0

        local window_sizes = { mock_window_size }

        for row in strategy:get_counters("my_namespace", window_sizes, mock_time) do
          i = i + 1
        end

        assert.equal(#expected_rows, i)
      end)
    end)

    describe(":purge()", function()
      db:query("TRUNCATE rl_counters")
      local windows = { mock_window_size }
      strategy:push_diffs(diffs)
      strategy:push_diffs(new_diffs)
      it("should not purge mock_start and mock_prev_start", function()

        strategy:purge("my_namespace", windows, mock_start)

        local rows = assert(db:query("SELECT * FROM rl_counters"))
        assert.same(expected_rows, rows)

      end)
      it("should purge mock_prev_start window as start moved 60 seconds", function()
        local expected_rows = {
          {
            count        = 10,
            key          = "foo",
            namespace    = "my_namespace",
            window_size  = mock_window_size,
            window_start = mock_start,
          },
          {
            count        = 10,
            key          = "1.2.3.4",
            namespace    = "my_namespace",
            window_size  = mock_window_size,
            window_start = mock_start,
          },
        }
        strategy:purge("my_namespace", windows, mock_start + 60)

        local rows = assert(db:query("SELECT * FROM rl_counters"))
        assert.equal(2, #rows)
        assert.same(expected_rows, rows)
      end)
      it("should purge mock_start and mock_prev_start as start moved 120 seconds",
         function()
        strategy:purge("my_namespace", windows, mock_start + 120)

        local rows = assert(db:query("SELECT * FROM rl_counters"))
        assert.equal(0, #rows)
      end)
    end)
  end)
end
