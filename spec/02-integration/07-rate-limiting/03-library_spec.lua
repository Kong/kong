local ratelimit   = require "kong.tools.public.rate-limiting"
local spec_helpers = require "spec.helpers"
local conf_loader = require "kong.conf_loader"
local dao_factory = require "kong.dao.factory"

local function window_floor(size, time)
  return math.floor(time / size) * size
end

describe("rate-limiting", function()
  local kong_conf = assert(conf_loader(spec_helpers.test_conf_path))
  local dao = assert(dao_factory.new(kong_conf))

  setup(function()
    assert(dao.db:query("TRUNCATE TABLE rl_counters"))
  end)

  describe("new()", function()
    describe("returns true", function()
      after_each(function()
        ratelimit.clear_config()
      end)

      it("given a config with sane values", function()
        assert.is_true(ratelimit.new({
          dict        = "foo",
          sync_rate   = 10,
          strategy    = "postgres",
          dao_factory = dao,
        }))
      end)

      it("given a config with a custom namespace", function()
        assert.is_true(ratelimit.new({
          dict      = "foo",
          sync_rate = 10,
          strategy  = "postgres",
          namespace = "bar",
          dao_factory = dao,
        }))
      end)
    end)

    describe("errors", function()
      it("when opts is not a table", function()
        assert.has.error(function() ratelimit.new("foo") end,
          "opts must be a table")
      end)

      it("when namespace contains a pipe character", function()
        assert.has.error(function() ratelimit.new({
          dict      = "foo",
          sync_rate = 10,
          strategy  = "postgres",
          namespace = "ba|r",
          dao_factory = dao,
        }) end, "namespace must not contain a pipe char")
      end)

      it("when namespace is not a string", function()
        assert.has.error(function() ratelimit.new({
          dict      = "foo",
          sync_rate = 10,
          strategy  = "postgres",
          namespace = 12345,
          dao_factory = dao,
        }) end, "namespace must be a valid string")
      end)
      it("when namespace already exists", function()
        assert.is_true(ratelimit.new({
          dict      = "foo",
          sync_rate = 10,
          strategy  = "postgres",
          namespace = "bar",
          dao_factory = dao,
        }))

        assert.has.error(function() ratelimit.new({
          dict      = "foo",
          sync_rate = 10,
          strategy  = "postgres",
          namespace = "bar",
          dao_factory = dao,
        }) end, "namespace bar already exists")
      end)

      it("when dict is not a valid string", function()
        assert.has.error(function() ratelimit.new({
          dict      = "",
          sync_rate = 10,
        }) end, "given dictionary reference must be a string")

        assert.has.error(function() ratelimit.new({
          sync_rate = 10,
          strategy  = "postgres",
          dao_factory = dao,
        }) end, "given dictionary reference must be a string")
      end)

      it("when an invalid strategy is given", function()
        assert.has.error(function() ratelimit.new({
          dict      = "foo",
          sync_rate = 10,
          strategy  = "yomama",
          dao_factory = dao,
        }) end)
      end)

      it("when an invalid strategy is given", function()
        assert.has.error(function() ratelimit.new({
          dict      = "foo",
          sync_rate = "bar",
          strategy  = "postgres",
          dao_factory = dao,
        }) end, "sync rate must be a number")
      end)
    end)
  end)

  describe("library #flaky", function()
    local mock_start = window_floor(60, ngx.time())

    -- i have no fucking clue whats going on here, but something in the mock
    -- shm requires us to do _something_ on this dictionary before incr
    -- works properly. no fuckin idea. fuck it.
    do
      local _ = ngx.shared.foo:get("xxx")
    end

    setup(function()
      assert(ratelimit.new({
        dict      = "foo",
        sync_rate = 10,
        strategy  = "postgres",
        window_sizes = { 60 },
        dao_factory = dao,
      }))

      assert(ratelimit.new({
        dict      = "foo",
        sync_rate = 10,
        strategy  = "postgres",
        namespace = "other",
        window_sizes = { 60 },
        dao_factory = dao,
      }))

      assert(ratelimit.new({
        dict         = "foo",
        sync_rate    = -1,
        strategy     = "postgres",
        namespace    = "tiny",
        window_sizes = { 2 },
        dao_factory  = dao,
      }))

      assert(ratelimit.new({
        dict         = "foo",
        sync_rate    = 10,
        strategy     = "postgres",
        namespace    = "mock",
        window_sizes = { 60 },
        dao_factory  = dao,
      }))
    end)

    teardown(function()
      dao.db:query("TRUNCATE TABLE rl_counters")
    end)

    describe("increment()", function()
      describe("in a single namespace", function()
        it("auto creates a key", function()
          local n = ratelimit.increment("foo", 60, 1)
          assert.same(1, n)
        end)

        it("increments a key", function()
          local n = ratelimit.increment("foo", 60, 1)
          assert.same(2, n)
          n = ratelimit.increment("foo", 60, 1)
          assert.same(3, n)
        end)
      end)

      describe("in multiple namespaces", function()
        it("auto creates a key", function()
          local n = ratelimit.increment("bar", 60, 1)
          assert.same(1, n)

         local o = ratelimit.increment("bar", 60, 1, "other")
         assert.same(1, o)
        end)

        it("increments a key in the appropriate namespace", function()
          local n = ratelimit.increment("bar", 60, 1)
          assert.same(2, n)
          n = ratelimit.increment("bar", 60, 1)
          assert.same(3, n)

          n = ratelimit.increment("bar", 60, 1, "other")
          assert.same(2, n)
          n = ratelimit.increment("bar", 60, 1, "other")
          assert.same(3, n)
        end)
      end)

      describe("accepts a value defining how to associate the previous weight",
               function()
        local rate = 2

        before_each(function()
          -- sleep til the start of the next window
          ngx.sleep(rate - (ngx.now() - (math.floor(ngx.now() / rate) * rate)))
        end)

        it("associates to a calculated weight by default", function()
          local n
          local m, o = 5, 5
          for i = 1, m do
            n = ratelimit.increment("foo", rate, 1, "tiny")
            assert.same(i, n)
          end

          -- sleep to the end of our window plus a _bit_
          ngx.sleep(rate + 0.3)

          for i = 1, o do
            n = ratelimit.increment("foo", rate, 1, "tiny")
            assert.is_true(n > i and n <= m + o)
          end
        end)

        it("defines a static weight to send to sliding_window", function()
          local n
          local m, o = 5, 5
          for i = 1, m do
            n = ratelimit.increment("foo", rate, 1, "tiny", 0)
            assert.same(i, n)
          end

          -- sleep to the end of our window plus a _bit_
          ngx.sleep(rate + 0.3)

          for i = 1, o do
            n = ratelimit.increment("foo", rate, 1, "tiny", 0)
            assert.same(i, n)
          end

        end)
      end)
    end)

    describe("sync()", function()
      setup(function()

        -- insert new keys 'foo' and 'baz', which will be incremented
        -- and freshly inserted, respectively
        assert(dao.db:query(
[[
  INSERT INTO rl_counters (key, namespace, window_start, window_size, count)
    VALUES
  ('foo', 'mock', ]] .. mock_start .. [[, 60, 3),
  ('baz', 'mock', ]] .. mock_start .. [[, 60, 3)
]]
        ))
      end)

      it("updates the database with our diffs", function()
        ratelimit.increment("foo", 60, 3, "mock")
        ratelimit.sync(nil, "mock") -- sync the mock namespace

        local rows = assert(dao.db:query("SELECT * from rl_counters where key = 'foo' and namespace = 'mock'"))
        assert.same(6, rows[1].count)
        rows = assert(dao.db:query("SELECT * from rl_counters"))
        assert.same(2, #rows)
      end)

      it("updates the local shm with new values", function()
        assert.equals(0, ngx.shared.foo:get("mock|" .. mock_start .. "|60|foo|diff"))
        assert.equals(6, ngx.shared.foo:get("mock|" .. mock_start .. "|60|foo|sync"))
      end)

      it("does not adjust values in a separate namespace", function()
        assert.equals(3, ngx.shared.foo:get("other|" .. mock_start .. "|60|bar|diff"))
        assert.equals(0, ngx.shared.foo:get("other|" .. mock_start .. "|60|bar|sync"))
      end)

      it("does not adjust values in a separate namespace", function()
        pcall(function() ratelimit.sync(nil, "other") end)
        assert.equals(0, ngx.shared.foo:get("other|" .. mock_start .. "|60|bar|diff"))
        assert.equals(3, ngx.shared.foo:get("other|" .. mock_start .. "|60|bar|sync"))
      end)
    end)

    describe("sliding_window()", function()
      setup(function()
        ngx.shared.foo:set("mock|" .. mock_start - 60 .. "|60|foo|diff", 0)
        ngx.shared.foo:set("mock|" .. mock_start - 60 .. "|60|foo|sync", 10)

        ngx.shared.foo:set("mock|" .. mock_start .. "|60|foo|diff", 0)
        ngx.shared.foo:set("mock|" .. mock_start .. "|60|foo|sync", 0)

        assert(ratelimit.increment("foo", 60, 3, "mock"))
      end)

      it("returns a fraction of the previous window", function()
        local rate = ratelimit.sliding_window("foo", 60, nil, "mock")
        -- 10 for what we set in setup(), 3 from previous increments
        assert.is_true(rate < 13 and rate >= 3)
      end)

      it("automagically creates shm keys if they don't exist", function()
        local dne_key = "yomama"
        local dict_key = "mock|" .. mock_start .. "|60|" .. dne_key
        assert.is_nil(ngx.shared.foo:get(dict_key .. "|diff"))
        assert.is_nil(ngx.shared.foo:get(dict_key .. "|sync"))

        assert.equals(0, ratelimit.sliding_window(dne_key, 60, nil, "mock"))

        assert.equals(0, ngx.shared.foo:get(dict_key .. "|diff"))
        assert.equals(0, ngx.shared.foo:get(dict_key .. "|sync"))
      end)

      it("uses the appropriate namespace", function()
        assert(ratelimit.increment("bat", 60, 1, "mock"))
        assert.equals(1, ratelimit.sliding_window("bat", 60, nil, "mock"))
        assert.equals(0, ratelimit.sliding_window("bat", 60, nil, "other"))
      end)
    end)
  end)
end)
