-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local spec_helpers = require "spec.helpers"
local conf_loader = require "kong.conf_loader"
local DB = require "kong.db"
local tablex = require "pl.tablex"

local function window_floor(size, time)
  return math.floor(time / size) * size
end

local function db_not_off(db)
  return db and db.database ~= "off"
end

describe("rate-limiting", function()
  local kong_conf = assert(conf_loader(spec_helpers.test_conf_path))
  local ratelimit

  local new_db = assert(DB.new(kong_conf))
  assert(new_db:init_connector())
  local db = new_db.connector

  -- hook the ngx.log so that we can check the log easily in the unit tests
  local native_ngx_log
  local log_path

  setup(function()
    if db_not_off(db) then
      assert(db:query("TRUNCATE TABLE rl_counters"))
    end

    native_ngx_log = ngx.log
    log_path = os.tmpname()

    ngx.log = function(lvl, ...) -- luacheck: ignore
      local file = io.open(log_path, "a")
      file:write(...)
      file:write("\n")
      file:close()
    end

    -- require this after we hook the ngx.log
    package.loaded["kong.tools.public.rate-limiting"] = nil
    ratelimit = require "kong.tools.public.rate-limiting"
  end)

  teardown(function()
    if db_not_off(db) then
      assert(db:query("TRUNCATE TABLE rl_counters"))
    end

    ngx.log = native_ngx_log -- luacheck: ignore
    os.remove(log_path)
  end)

  -- this must be the first one to test because the warn log is only printed
  -- first time `new` is called
  describe("the deprecated way of initialization of the library", function()
    it("print a warn log when the library is used without correctly initialized", function()
      local rl = require("kong.tools.public.rate-limiting")
      assert.is_true(rl.new({
        dict      = "avoid-conflict",
        sync_rate = 10,
        strategy  = "postgres",
        namespace = "avoid-conflict",
        db = new_db,
      }))

      assert.logfile(log_path).has.line("Your plugin is using a deprecated "
      .. "interface to initialize the rate limiting library. To avoid potential"
      .. " race conditions or other unexpected behaviors, the plugin code should"
      .. " be updated to use new initialization function like", true)
    end)

    describe("when redis strategy", function()
      local library_config_template = {
        dict      = "avoid-conflict",
        sync_rate = 10,
        strategy  = "redis",
        strategy_opts = {}
      }
      local library_config_1 = tablex.merge(library_config_template, { namespace = "avoid-conflict-1" }, true)
      local library_config_2 = tablex.merge(library_config_template, { namespace = "avoid-conflict-2" }, true)
      local library_config_3 = tablex.merge(library_config_template, { namespace = "avoid-conflict-3" }, true)

      local function clean_logfile()
        local file = io.open(log_path, "w")
        file:write("")
        file:close()
      end

      before_each(function()
        clean_logfile()
      end)

      after_each(function()
        clean_logfile()
      end)

      it("print a warn log when the library is used but initialized in old way", function()
        local rl = require("kong.tools.public.rate-limiting")
        assert.is_true(rl.new(library_config_1))

        assert.logfile(log_path).has.line("[rate-limiting] Your plugin is using rate-limiting library with redis strategy without " ..
          "specifying redis_config_version. If a plugin instance will use redis storage strategy it will default to old redis " ..
          "configuration for backwards compatibility but this deprecated configuration version will be " ..
          "removed in the upcoming major release. Please update your plugin to use new initialization function like:", true)
      end)

      it("print a warn log when the library is used correctly initialized but without redis config version", function()
        local rl_instance = require("kong.tools.public.rate-limiting").new_instance("test-config")
        assert.is_true(rl_instance.new(library_config_2))

        assert.logfile(log_path).has.line("[test-config] Your plugin is using rate-limiting library with redis strategy without " ..
          "specifying redis_config_version. If a plugin instance will use redis storage strategy it will default to old redis " ..
          "configuration for backwards compatibility but this deprecated configuration version will be " ..
          "removed in the upcoming major release. Please update your plugin to use new initialization function like:", true)
      end)

      it("print a warn log when the library is used without correctly initialized redis config version", function()
        local rl_instance = require("kong.tools.public.rate-limiting").new_instance("test-config", { redis_config_version = "v2" })
        assert.is_true(rl_instance.new(library_config_3))

        assert.logfile(log_path).has.no.line("[test-config] Your plugin is using rate-limiting library with redis strategy without " ..
          "specifying redis_config_version. If a plugin instance will use redis storage strategy it will default to old redis " ..
          "configuration for backwards compatibility but this deprecated configuration version will be " ..
          "removed in the upcoming major release. Please update your plugin to use new initialization function like:", true)
      end)
    end)
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
          db = new_db,
        }))
      end)

      it("given a config with a custom namespace", function()
        assert.is_true(ratelimit.new({
          dict      = "foo",
          sync_rate = 10,
          strategy  = "postgres",
          namespace = "bar",
          db = new_db,
        }))
      end)

      it("given a config with sync_rate as '-1'", function()
        assert.is_true(ratelimit.new({
          dict      = "foo",
          sync_rate = -1,
          strategy  = "postgres",
          namespace = "bar",
          db = new_db,
        }))
      end)

      it("given a config with strategy as 'off'", function()
        assert.is_true(ratelimit.new({
          dict      = "foo",
          sync_rate = 10,
          strategy  = "off",
          namespace = "bar",
          db = new_db,
        }))
      end)

      it("given a config with sync_rate as '-1' and strategy as 'off'", function()
        assert.is_true(ratelimit.new({
          dict      = "foo",
          sync_rate = -1,
          strategy  = "off",
          namespace = "bar",
          db = new_db,
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
          db = db,
        }) end, "namespace must not contain a pipe char")
      end)

      it("when namespace is not a string", function()
        assert.has.error(function() ratelimit.new({
          dict      = "foo",
          sync_rate = 10,
          strategy  = "postgres",
          namespace = 12345,
          db = db,
        }) end, "namespace must be a valid string")
      end)

      it("when namespace already exists", function()
        assert.is_true(ratelimit.new({
          dict      = "foo",
          sync_rate = 10,
          strategy  = "postgres",
          namespace = "bar",
          db = new_db,
        }))

        assert.has.error(function() ratelimit.new({
          dict      = "foo",
          sync_rate = 10,
          strategy  = "postgres",
          namespace = "bar",
          db = new_db,
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
          db = new_db,
        }) end, "given dictionary reference must be a string")
      end)

      it("when an invalid strategy is given", function()
        assert.has.error(function() ratelimit.new({
          dict      = "foo",
          sync_rate = 10,
          strategy  = "yomama",
          db = new_db,
        }) end)
      end)

      it("when an invalid sync_rate is given", function()
        assert.has.error(function() ratelimit.new({
          dict      = "foo",
          sync_rate = "bar",
          strategy  = "postgres",
          db = new_db,
        }) end, "sync rate must be a number")
      end)
    end)
  end)

  describe("update()", function()
    describe("returns true", function()
      before_each(function()
        ratelimit.clear_config()
        assert.is_true(ratelimit.new({
          dict      = "foo",
          sync_rate = 10,
          strategy  = "postgres",
          namespace = "bar",
          db = new_db,
        }))
      end)
      after_each(function()
        ratelimit.clear_config()
      end)

      it("given a config with sane values", function()
        assert.is_true(ratelimit.new({
          dict        = "foo",
          sync_rate   = 10,
          strategy    = "postgres",
          db = new_db,
        }))

        assert.is_true(ratelimit.update({
          dict        = "foo",
          sync_rate   = 9,
          strategy    = "postgres",
          db = new_db,
        }))
      end)

      it("given a config with a custom namespace", function()
        assert.is_true(ratelimit.update({
          dict      = "foo",
          sync_rate = 9,
          strategy  = "postgres",
          namespace = "bar",
          db = new_db,
        }))
      end)

      it("given a config with sync_rate as '-1'", function()
        assert.is_true(ratelimit.update({
          dict      = "foo",
          sync_rate = -1,
          strategy  = "postgres",
          namespace = "bar",
          db = new_db,
        }))
      end)

      it("given a config with strategy as 'off'", function()
        assert.is_true(ratelimit.update({
          dict      = "foo",
          sync_rate = 10,
          strategy  = "off",
          namespace = "bar",
          db = new_db,
        }))
      end)

      it("given a config with sync_rate as '-1' and strategy as 'off'", function()
        assert.is_true(ratelimit.update({
          dict      = "foo",
          sync_rate = -1,
          strategy  = "off",
          namespace = "bar",
          db = new_db,
        }))
      end)
    end)

    describe("errors", function()
      before_each(function()
        ratelimit.clear_config()
        assert.is_true(ratelimit.new({
          dict      = "foo",
          sync_rate = 10,
          strategy  = "postgres",
          namespace = "bar",
          db = new_db,
        }))
      end)
      after_each(function()
        ratelimit.clear_config()
      end)

      it("when opts is not a table", function()
        assert.has.error(function() ratelimit.update("foo") end,
          "opts must be a table")
      end)

      it("when namespace contains a pipe character", function()
        assert.has.error(function() ratelimit.update({
          dict      = "foo",
          sync_rate = 10,
          strategy  = "postgres",
          namespace = "ba|r",
          db = db,
        }) end, "namespace must not contain a pipe char")
      end)

      it("when namespace doesn't exist", function()
        assert.has.error(function() ratelimit.update({
          dict      = "foo",
          sync_rate = 10,
          strategy  = "postgres",
          namespace = "nonexistent",
          db = db,
        }) end, "namespace nonexistent doesn't exist")
      end)

      it("when namespace is not a string", function()
        assert.has.error(function() ratelimit.update({
          dict      = "foo",
          sync_rate = 10,
          strategy  = "postgres",
          namespace = 12345,
          db = db,
        }) end, "namespace must be a valid string")
      end)

      it("when dict is not a valid string", function()
        assert.has.error(function() ratelimit.update({
          dict      = "",
          sync_rate = 10,
          namespace = "bar",
        }) end, "given dictionary reference must be a string")

        assert.has.error(function() ratelimit.update({
          sync_rate = 10,
          strategy  = "postgres",
          db = new_db,
          namespace = "bar",
        }) end, "given dictionary reference must be a string")
      end)

      it("when an invalid strategy is given", function()
        assert.has.error(function() ratelimit.update({
          dict      = "foo",
          sync_rate = 10,
          strategy  = "yomama",
          db = new_db,
          namespace = "bar",
        }) end)
      end)

      it("when an invalid sync_rate is given", function()
        assert.has.error(function() ratelimit.update({
          dict      = "foo",
          sync_rate = "bar",
          strategy  = "postgres",
          db = new_db,
          namespace = "bar",
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
        db = new_db,
      }))

      assert(ratelimit.new({
        dict      = "foo",
        sync_rate = 10,
        strategy  = "postgres",
        namespace = "other",
        window_sizes = { 60 },
        db = new_db,
      }))

      assert(ratelimit.new({
        dict         = "foo",
        sync_rate    = -1,
        strategy     = "postgres",
        namespace    = "tiny",
        window_sizes = { 2 },
        db = new_db,
      }))

      assert(ratelimit.new({
        dict         = "foo",
        sync_rate    = 10,
        strategy     = "postgres",
        namespace    = "mock",
        window_sizes = { 60 },
        db = new_db,
      }))

      assert(ratelimit.new({
        dict         = "off",
        sync_rate    = -1,
        strategy     = "off",
        namespace    = "nodb",
        window_sizes = { 60 },
        db = new_db,
      }))

      assert(ratelimit.new({
        dict         = "off",
        sync_rate    = -1,
        strategy     = "off",
        namespace    = "nodbweight",
        window_sizes = { 60 },
        db = new_db,
      }))

      assert(ratelimit.new({
        dict         = "foo",
        sync_rate    = 5,
        strategy     = "postgres",
        namespace    = "one",
        window_sizes = { 1 },
        db = new_db,
      }))

      assert(ratelimit.new({
        dict         = "foo",
        sync_rate    = 2,
        strategy     = "postgres",
        namespace    = "two",
        window_sizes = { 3 },
        db = new_db,
      }))
    end)

    teardown(function()
      if db_not_off(db) then
        assert(db:query("TRUNCATE TABLE rl_counters"))
      end
    end)

    describe("increment()", function()
      describe("in a single namespace", function()
        it("auto creates a key", function()
          local n = ratelimit.increment("foo", 60, 1)
          assert.same(1, n)

          n = ratelimit.increment("off", 60, 1, "nodb")
          assert.same(1, n)
        end)

        it("increments a key", function()
          local n = ratelimit.increment("foo", 60, 1)
          assert.same(2, n)
          n = ratelimit.increment("foo", 60, 1)
          assert.same(3, n)

          n = ratelimit.increment("off", 60, 1, "nodb")
          assert.same(2, n)
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

          n = ratelimit.increment("off", 60, 1, "nodb")
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

          for i = 1, m do
            n = ratelimit.increment("off", rate, 1, "nodbweight")
            assert.same(i, n)
          end

          -- sleep to the end of our window plus a _bit_
          ngx.sleep(rate + 0.3)

          for i = 1, o do
            n = ratelimit.increment("foo", rate, 1, "tiny")
            assert.is_true(n >i and n <= m + o)
          end

          for i = 1, o do
            n = ratelimit.increment("off", rate, 1, "nodbweight")
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

          for i = 1, m do
            n = ratelimit.increment("off", rate, 1, "nodbweight", 0)
            assert.same(i, n)
          end

          -- sleep to the end of our window plus a _bit_
          ngx.sleep(rate + 0.3)

          for i = 1, o do
            n = ratelimit.increment("foo", rate, 1, "tiny", 0)
            assert.same(i, n)
          end

          for i = 1, o do
            n = ratelimit.increment("off", rate, 1, "nodbweight", 0)
            assert.same(i, n)
          end
        end)
      end)
    end)

    if db_not_off(db) then
      describe("sync()", function()
        setup(function()

          -- insert new keys 'foo' and 'baz', which will be incremented
          -- and freshly inserted, respectively
          assert(db:query(
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

          local rows = assert(db:query("SELECT * from rl_counters where key = 'foo' and namespace = 'mock'"))
          assert.same(6, rows[1].count)
          rows = assert(db:query("SELECT * from rl_counters"))
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

        -- sync_rate = 5, window_size = 1
        it("sync_rate > window_size * 2, expires after sync_rate", function()
          local jitter = 1

          local mock_window = window_floor(1, ngx.time())
          ratelimit.increment("foo", 1, 1, "one")

          ngx.sleep(2 + jitter)   -- greater than window_size * 2
          pcall(function() ratelimit.sync(nil, "one") end)
          assert.equals(0, ngx.shared.foo:get("one|" .. mock_window .. "|1|foo|diff"))
          assert.equals(1, ngx.shared.foo:get("one|" .. mock_window .. "|1|foo|sync"))

          ngx.sleep(5 - 2)
          assert.equals(nil, ngx.shared.foo:get("one|" .. mock_window .. "|1|foo|diff"))
          assert.equals(nil, ngx.shared.foo:get("one|" .. mock_window .. "|1|foo|sync"))
        end)

        -- sync_rate = 2, window_size = 3
        it("window_size * 2 > sync_rate, expires after window_size*2", function()
          local jitter = 1

          local mock_window = window_floor(3, ngx.time())
          ratelimit.increment("foo", 3, 1, "two")

          ngx.sleep(2 + jitter)   -- greater than sync_rate
          pcall(function() ratelimit.sync(nil, "two") end)
          assert.equals(0, ngx.shared.foo:get("two|" .. mock_window .. "|3|foo|diff"))
          assert.equals(1, ngx.shared.foo:get("two|" .. mock_window .. "|3|foo|sync"))

          ngx.sleep(3 * 2 - 2)
          assert.equals(nil, ngx.shared.foo:get("two|" .. mock_window .. "|3|foo|diff"))
          assert.equals(nil, ngx.shared.foo:get("two|" .. mock_window .. "|3|foo|sync"))
        end)
      end)
    end

    describe("sliding_window()", function()
      setup(function()
        ngx.shared.foo:set("mock|" .. mock_start - 60 .. "|60|foo|diff", 0)
        ngx.shared.foo:set("mock|" .. mock_start - 60 .. "|60|foo|sync", 10)

        ngx.shared.foo:set("mock|" .. mock_start .. "|60|foo|diff", 0)
        ngx.shared.foo:set("mock|" .. mock_start .. "|60|foo|sync", 0)

        assert.has_no.errors(function()
          assert(ratelimit.increment("foo", 60, 3, "mock"))
        end)

        ngx.shared.foo:set("nodb|" .. mock_start - 60 .. "|60|off|diff", 0)
        ngx.shared.foo:set("nodb|" .. mock_start - 60 .. "|60|off|sync", 10)

        ngx.shared.foo:set("nodb|" .. mock_start .. "|60|off|diff", 0)
        ngx.shared.foo:set("nodb|" .. mock_start .. "|60|off|sync", 10)

        assert.has_no.errors(function()
          ratelimit.increment("off", 60, 3, "nodb")
        end)
      end)

      it("returns a fraction of the previous window", function()
        local rate = ratelimit.sliding_window("foo", 60, nil, "mock")
        -- 10 for what we set in setup(), 3 from previous increments
        assert.is_true(rate < 13 and rate >= 3)

        rate = ratelimit.sliding_window("off", 60, nil, "nodb")
        ngx.say("rate = ", rate)
        assert.is_true(rate < 7 and rate >= 3)
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

  describe("multiple instances", function()
    local ratelimit = require("kong.tools.public.rate-limiting")
    local rl1 = ratelimit.new_instance("plugin1")
    local rl2 = ratelimit.new_instance("plugin2")

    it("instances should be isolated from each other", function()
      assert.is_true(rl1.new({
        dict      = "foo",
        sync_rate = 10,
        strategy  = "postgres",
        namespace = "bar",
        db = new_db,
      }))

      assert.is_true(rl2.new({
        dict      = "fee",
        sync_rate = 5,
        strategy  = "postgres",
        namespace = "bar",
        db = new_db,
      }))

      assert.is_true(rl2.new({
        dict      = "faa",
        sync_rate = 3,
        strategy  = "postgres",
        namespace = "baz",
        db = new_db,
      }))

      -- rl1.config only contains one element
      local index = assert(next(rl1.config))
      assert.is_nil(next(rl1.config, index))

      -- rl2.config contains two elements
      index = assert(next(rl2.config))
      index = assert(next(rl2.config, index))
      assert.is_nil(next(rl2.config, index))

      assert(rl1.config["bar"])
      assert.same("foo", rl1.config["bar"].dict)
      assert.same(10, rl1.config["bar"].sync_rate)

      assert(rl2.config["bar"])
      assert.same("fee", rl2.config["bar"].dict)
      assert.same(5, rl2.config["bar"].sync_rate)

      assert(rl2.config["baz"])
      assert.same("faa", rl2.config["baz"].dict)
      assert.same(3, rl2.config["baz"].sync_rate)
    end)
  end)
end)
