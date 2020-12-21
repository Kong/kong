local utils = require "kong.tools.utils"
local deep_copy = utils.deep_copy
local split = utils.split

local fmt = string.format

describe("sandbox functions wrapper", function()

  local sandbox, sandbox_helpers, load_s

  local base_conf = {
    untrusted_lua_sandbox_requires = {},
    untrusted_lua_sandbox_environment = {},
  }

  _G.kong = {
    configuration = {},
  }

  lazy_setup(function()
    _G.kong.configuration = deep_copy(base_conf)

    -- load and reference module we can spy on
    _G.load = spy.new(load)
    sandbox = spy.new(require "kong.tools.sandbox")
    package.loaded["kong.tools.sandbox"] = sandbox
    sandbox_helpers = require "kong.tools.sandbox_helpers"
  end)

  before_each(function()
    sandbox:clear()
    load:clear()
    sandbox_helpers.configuration:reload()
  end)

  lazy_teardown(function()
    load:revert()
    sandbox:revert()
  end)

  describe("#sandbox_helpers.validate", function()
    for _, u in ipairs({'on', 'sandbox'}) do describe(("untrusted_lua = '%s'"):format(u), function()
      lazy_setup(function()
        _G.kong.configuration.untrusted_lua = u
      end)

      lazy_teardown(function()
        _G.kong.configuration = deep_copy(base_conf)
      end)

      it("validates input is lua that returns a function", function()
        assert.is_true(sandbox_helpers.validate("return function() end"))
      end)

      it("returns false and error when some string is not some code", function()
        local ok, err = sandbox_helpers.validate("here come the warm jets")
        assert.is_false(ok)
        assert.matches("Error parsing function", err, nil, true)
      end)

      it("returns false and error when input is lua that does not return a function", function()
        local ok, err = sandbox_helpers.validate("return 42")
        assert.is_false(ok)
        assert.matches("Bad return value from function, expected function type, got number", err)
      end)
    end) end

    describe("untrusted_lua = 'off'", function()
      lazy_setup(function()
        _G.kong.configuration.untrusted_lua = 'off'
      end)

      lazy_teardown(function()
        _G.kong.configuration = deep_copy(base_conf)
      end)

      it("errors", function()
        local ok, err = sandbox_helpers.validate("return function() end")
        assert.is_false(ok)
        assert.matches(sandbox_helpers.configuration.err_msg, err, nil, true)
      end)
    end)
  end)

  describe("#sandbox_helpers.sandbox", function()
    local setting

    before_each(function()
      _G.kong.configuration.untrusted_lua = setting
    end)

    lazy_teardown(function()
      _G.kong.configuration = deep_copy(base_conf)
    end)

    describe("untrusted_lua = 'off'", function()
      lazy_setup(function() setting = 'off' end)

      it("errors", function()
        sandbox_helpers.configuration:reload()
        assert.error(function() sandbox_helpers.sandbox("return 42") end)
      end)
    end)

    local function load_t()
      sandbox_helpers.sandbox("return 42")
      assert.spy(load).was.called()
      assert.equal("t", load.calls[1].vals[3])
    end

    local function load_b_err()
      assert.error(function()
        sandbox_helpers.sandbox(string.dump(function() end))
      end)
    end


    describe("untrusted_lua = 'on'", function()
      lazy_setup(function() setting = 'on' end)

      it("does not use sandbox", function()
        assert(sandbox_helpers.sandbox('return 42')())
        assert.spy(sandbox).was_not.called()
      end)

      it("calls load with mode t (text only)", function()
        sandbox_helpers.sandbox("return 42")
        assert.spy(load).was.called()
        assert.equal("t", load.calls[1].vals[3])
      end)

      it("does not load binary strings (text only)", function()
        assert.error(function()
          sandbox_helpers.sandbox(string.dump(function() end))
        end)
      end)

      describe("environment", function()
        lazy_setup(function()
          _G.hello_world = "Hello World"
        end)

        lazy_teardown(function()
          _G.hello_world = nil
        end)

        it("has _G access", function()
          assert.same(_G.hello_world, sandbox_helpers.sandbox('return hello_world')())
        end)

        it("does not write _G", function()
          local r = sandbox_helpers.sandbox('hello_world = "foobar" return hello_world')()
          assert.same("foobar", r)
          assert.same("Hello World", _G.hello_world)
        end)

        it("does use an environment too", function()
          local env = { foo = 0}
          local fn = sandbox_helpers.parse([[
            return function(inc)
              foo = foo + inc
            end
          ]], { env = env })
          fn(10) fn(20) fn(30)
          assert.equal(60, env.foo)
        end)
      end)
    end)

    describe("untrusted_lua = 'sandbox'", function()
      lazy_setup(function() setting = 'sandbox' end)

      it("calls sandbox.lua behind the scenes", function()
        sandbox_helpers.sandbox("return 42")
        assert.spy(sandbox).was.called()
      end)

      it("calls load with mode t (text only)", function()
        sandbox_helpers.sandbox("return 42")
        assert.spy(load).was.called()
        assert.equal("t", load.calls[1].vals[3])
      end)

      it("does not load binary strings (text only)", function()
        assert.error(function()
          sandbox_helpers.sandbox(string.dump(function() end))
        end)
      end)

      -- XXX These could be more or less more attractive to the eyes
      describe("environment", function()
        local requires = { "foo", "bar", "baz" }
        local modules = {
          "foo.bar",
          "bar",
          "baz.fuzz.answer",
          "fizz.fizz", "fizz.buzz", "fizz.zap",
        }

        local function find(q, o)
          if not q then return o end
          local h, r = table.unpack(split(q, '.', 2))
          return find(r, o[h])
        end

        lazy_setup(function()
          _G.foo = { bar = { hello = "world" }, baz = "fuzz" }
          _G.bar = { "baz", "fuzz", { bye = "world" } }
          _G.baz = { foo = _G.foo, fuzz = { question = "everything", answer = 42 } }
          _G.fizz = { fizz = _G.foo, buzz = _G.bar, zap = _G.baz }

          _G.kong.configuration.untrusted_lua_sandbox_requires = requires
          _G.kong.configuration.untrusted_lua_sandbox_environment = modules
        end)

        lazy_teardown(function()
          _G.foo = nil
          _G.bar = nil
          _G.baz = nil
          _G.fizz = nil

          _G.kong.configuration = deep_copy(base_conf)
        end)

        it("has access to config.untrusted_lua_sandbox_environment", function()
          for _, m in ipairs(modules) do
            assert.same(find(m, _G), sandbox_helpers.sandbox(fmt("return %s", m))())
          end
        end)

        it("does not have access to anything else on the modules", function()
          for _, m in ipairs({ "foo.baz", "baz.foo", "baz.fuzz.question"}) do
            assert.is_nil(sandbox_helpers.sandbox(fmt("return %s", m))())
          end
        end)

        it("tables are read only", function()
          sandbox_helpers.sandbox([[ foo.bar.something = 'hello' ]])()
          assert.is_nil(_G.foo.bar.something)
        end)

        it("tables are unmutable on all levels", function()
          sandbox_helpers.sandbox([[ baz.fuzz.hallo = 'hello' ]])()
          assert.is_nil(_G.baz.fuzz.hallo)
        end)

        it("configuration.untrusted_lua_sandbox_environment is composable", function()
          local s_fizz = sandbox_helpers.sandbox([[ return fizz ]])()
          assert.same(_G.fizz, s_fizz)
        end)

        pending("opts.env is composable with sandbox_environment", function()
          local some_env = {
            foo = {
              something = { fun = function() end },
            }
          }
          local s_foo = sandbox_helpers.sandbox([[
            return foo
          ]], { env = some_env })()

          assert.same({
            bar = { hello = "world" },
            something = some_env.foo.something,
          }, s_foo)
        end)

        describe("fake require", function()
          it("can require config.untrusted_lua_sandbox_requires", function()
            for _, mod in ipairs(requires) do
                local mock = function() end
                local _o = package.loaded[mod]
                package.loaded[mod] = mock

                local fn = string.format("return require('%s')", mod)
                assert.equal(mock, sandbox_helpers.sandbox(fn)())

                finally(function() package.loaded[mod] = _o end)
            end
          end)

          it("cannot require anything else", function()
            local fn = sandbox_helpers.sandbox("return require('something-else')")
            local _, err = pcall(fn)
            assert.matches("require 'something-else' not allowed", err, nil, true)
          end)
        end)
      end)
    end)

  end)

  describe("#sandbox_helpers.parse", function()
    for _, u in ipairs({'on', 'sandbox'}) do describe(("untrusted_lua = '%s'"):format(u), function()
      lazy_setup(function()
        _G.kong.configuration.untrusted_lua = u
      end)

      lazy_teardown(function()
        _G.kong.configuration = deep_copy(base_conf)
      end)

      it("returns a function when it gets code returning a function", function()
        local fn = sandbox_helpers.parse([[
          return function(something)
            return something
          end
        ]])
        assert.equal("function", type(fn))
        assert.equal("foobar", fn("foobar"))
      end)

      describe("errs with invalid input:", function()
        it("bad code", function()
          assert.error(function() sandbox_helpers.parse("foo bar baz") end)
        end)

        it("code that does not return a function", function()
          assert.error(function() sandbox_helpers.parse("return 42") end)
        end)
      end)
    end) end

    describe("untrusted_lua = 'off'", function()
      lazy_setup(function()
        _G.kong.configuration.untrusted_lua = 'off'
      end)

      lazy_teardown(function()
        _G.kong.configuration = deep_copy(base_conf)
      end)

      it("errors", function()
        assert.error(function() sandbox_helpers.parse("return 42") end)
      end)
    end)
  end)
end)
