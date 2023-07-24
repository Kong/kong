-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local redis_strategy = require "kong.tools.public.rate-limiting.strategies.redis"
local redis = require "resty.redis"
local helpers = require "spec.helpers"
local ee_helpers = require "spec-ee.helpers"


require"kong.resty.dns.client".init(nil)

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

describe("public tool rate-limiting redis cluster", function()
  local config, redis_cluster
  local key, window, size, namespace, time

  config = {
    ok_conf = {
      connect_timeout = 100,
      send_timeout    = 100,
      read_timeout    = 100,
      keepalive_pool_size = 5,
      keepalive_backlog = 5,
      cluster_addresses = ee_helpers.redis_cluster_addresses,
    },
    err_conf = {
      connect_timeout = 100,
      send_timeout    = 100,
      read_timeout    = 100,
      keepalive_pool_size = 5,
      keepalive_backlog = 5,
      cluster_addresses = { "localhost:7654" },
    },
    err_sentinel_conf = {
      connect_timeout = 100,
      send_timeout    = 100,
      read_timeout    = 100,
      keepalive_pool_size = 5,
      keepalive_backlog = 5,
      sentinel_addresses = { "localhost:7654", "localhost:7655", "localhost:7656" },
    },
  }

  key = "df52e254-a4a1-5b08-a5b0-b9ba1e5948d4"
  window = 1679037600
  size = 60
  namespace = "Kma6XU50u8rDZvalU3uf8Xs1JnFtZna7"
  time = window + 10

  it("valid addresses does not return error", function()
    local _, err
    redis_cluster = redis_strategy.new(nil, config.ok_conf)

    _, err = redis_cluster:get_counters(namespace, { size }, time)
    assert.is_nil(err)

    _, err = redis_cluster:get_window(key, namespace, window, size)
    assert.is_nil(err)
  end)

  it("invalid addresses must return error", function()
    local _, err
    redis_cluster = redis_strategy.new(nil, config.err_conf)

    _, err = redis_cluster:get_counters(namespace, { size }, time)
    assert.is_not_nil(err)
    assert(err:find("failed to fetch slots: connection refused", nil, true))

    _, err = redis_cluster:get_window(key, namespace, window, size)
    assert.is_not_nil(err)
    assert(err:find("failed to fetch slots: connection refused", nil, true))
  end)

  it("invalid sentinel addresses must return previous error", function()
    local _, err
    redis_cluster = redis_strategy.new(nil, config.err_sentinel_conf)

    _, err = redis_cluster:get_counters(namespace, { size }, time)
    assert.is_not_nil(err)
    assert(err:find("previous errors: connection refused, connection refused, connection refused",
                    nil, true))
  end)
end)
