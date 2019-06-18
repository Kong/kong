local redis_strategy = require "kong.tools.public.rate-limiting.strategies.redis"
local redis = require "resty.redis"
local helpers = require "spec.helpers"


require"resty.dns.client".init(nil)

local function window_floor(size, time)
  return math.floor(time / size) * size
end

describe("rate-limiting: Redis strategy", function()
  local strategy, redis_client

  local mock_time = ngx.time()
  local mock_window_size = 60

  local mock_namespace = "default"
  local mock_start = window_floor(mock_window_size, mock_time)
  local mock_prev_start = window_floor(mock_window_size, mock_time) -
                          mock_window_size

  local mock_red_key = mock_start .. ":" .. mock_window_size .. ":" ..
                       mock_namespace
  local mock_prev_red_key = mock_prev_start .. ":" .. mock_window_size .. ":" ..
                            mock_namespace

  local redis_opts = {
    host = helpers.redis_host,
    port = 6379,
    database = 0,
  }

  setup(function()
    strategy = redis_strategy.new(nil, redis_opts)
    redis_client = redis:new()
    redis_client:connect(redis_opts.host, redis_opts.port)
  end)

  teardown(function()
    redis_client:flushall()
  end)

  local diffs = {
    {
      key     = "foo",
      windows = {
        {
          namespace = mock_namespace,
          window    = mock_start,
          size      = mock_window_size,
          diff      = 5,
        },
        {
          namespace = mock_namespace,
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
          namespace = mock_namespace,
          window    = mock_start,
          size      = mock_window_size,
          diff      = 5,
        },
        {
          namespace = mock_namespace,
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
          namespace = mock_namespace,
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
          namespace = mock_namespace,
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
      namespace    = mock_namespace,
      window_size  = mock_window_size,
      window_start = mock_prev_start,
    },
    {
      count        = 1,
      key          = "1.2.3.4",
      namespace    = mock_namespace,
      window_size  = mock_window_size,
      window_start = mock_prev_start,
    },
    {
      count        = 10,
      key          = "foo",
      namespace    = mock_namespace,
      window_size  = mock_window_size,
      window_start = mock_start,
    },
    {
      count        = 10,
      key          = "1.2.3.4",
      namespace    = mock_namespace,
      window_size  = mock_window_size,
      window_start = mock_start,
    },
  }

  describe(":push_diffs()", function()
    it("pushes a diffs structure to the counters column_family", function()

      -- no return values
      strategy:push_diffs(diffs)

      -- push diffs with existing values in redis
      strategy:push_diffs(new_diffs)

      -- check
      -- note that redis gives us back strings
      local hash = assert(redis_client:array_to_hash(redis_client:hgetall(mock_red_key)))
      assert.same({ foo = "10", ["1.2.3.4"] = "10" }, hash)
      hash = assert(redis_client:array_to_hash(redis_client:hgetall(mock_prev_red_key)))
      assert.same({ foo = "2", ["1.2.3.4"] = "1" }, hash)
    end)
    it("expires old window data", function()
      local mock_namespace_expire = mock_namespace .. "_expire_test"
      local mock_window_size_short = 1
      local diff = {
        {
          key     = "foo",
          windows = {
            {
              namespace = mock_namespace_expire,
              window    = mock_start,
              size      = mock_window_size_short,
              diff      = 5,
            },
          }
        },
      }
      local mock_prev_red_key = mock_start .. ":" .. mock_window_size_short .. ":" ..
                                mock_namespace_expire
      strategy:push_diffs(diff)
      assert.equal(1, redis_client:exists(mock_prev_red_key))

      -- wait a little more than 2 * window size for key to expire
      ngx.sleep(2 * mock_window_size_short + 1)
      assert.equal(0, redis_client:exists(mock_prev_red_key))
    end)
  end)

  describe(":get_window()", function()
    it("retrieves the counter for a given window", function()
      local count = assert(strategy:get_window("1.2.3.4", mock_namespace,
                                               mock_start, mock_window_size))
      assert.equal(10, count)

      count = assert(strategy:get_window("1.2.3.4", mock_namespace,
                                         mock_prev_start, mock_window_size))
      assert.equal(1, count)

      count = assert(strategy:get_window("foo", mock_namespace, mock_start,
                                         mock_window_size))
      assert.equal(10, count)

      count = assert(strategy:get_window("foo", mock_namespace, mock_prev_start,
                                         mock_window_size))
      assert.equal(2, count)
    end)
  end)

  describe(":get_counters()", function()
    -- setup our extra rows to simulate old entries
    setup(function()
      local mock_key = mock_start - 3 * mock_window_size .. ":" ..
                       mock_window_size .. ":" .. mock_namespace
      redis_client:hincrby(mock_key, "1.2.3.4", 9)
    end)

    it("iterates over each window for each key", function()
      local i = 0

      local window_sizes = { mock_window_size }

      for row in strategy:get_counters(mock_namespace, window_sizes, mock_time) do
        i = i + 1
      end

      assert.equal(#expected_rows, i)
    end)
  end)
end)
