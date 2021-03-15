local utils = require "kong.tools.utils"


local deep_copy = utils.deep_copy
local fmt = string.format

describe("sandbox functions wrapper", function()

  local _sandbox, sandbox, load_s

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
    load_s = spy.new(load)
    _G.load = load_s
    _sandbox = spy.new(require "sandbox")
    package.loaded["sandbox"] = _sandbox
    sandbox = require "kong.tools.sandbox"
  end)

  before_each(function()
    _sandbox:clear()
    load_s:clear()
    sandbox.configuration:clear()
  end)

  lazy_teardown(function()
    load_s:revert()
    _sandbox:revert()
  end)

  describe("sandbox.validate_safe", function()
    for _, u in ipairs({'on', 'sandbox'}) do describe(("untrusted_lua = '%s'"):format(u), function()
      lazy_setup(function()
        _G.kong.configuration.untrusted_lua = u
      end)

      lazy_teardown(function()
        _G.kong.configuration = deep_copy(base_conf)
      end)

      -- https://github.com/Kong/kong/issues/5110
      it("does not execute the code itself", function()
        local env = { do_it = spy.new(function() end) }
        local ok = sandbox.validate_safe([[ do_it() ]], { env = env })
        assert.is_true(ok)
        assert.spy(env.do_it).not_called()

        -- and now, of course, for the control group!
        sandbox.sandbox([[ do_it() ]], { env = env })()
        assert.spy(env.do_it).called()
      end)
    end) end
  end)

  describe("sandbox.validate", function()
    for _, u in ipairs({'on', 'sandbox'}) do describe(("untrusted_lua = '%s'"):format(u), function()
      lazy_setup(function()
        _G.kong.configuration.untrusted_lua = u
      end)

      lazy_teardown(function()
        _G.kong.configuration = deep_copy(base_conf)
      end)

      it("validates input is lua that returns a function", function()
        assert.is_true(sandbox.validate("return function() end"))
      end)

      it("returns false and error when some string is not some code", function()
        local ok, err = sandbox.validate("here come the warm jets")
        assert.is_false(ok)
        assert.matches("Error parsing function", err, nil, true)
      end)

      it("returns false and error when input is lua that produces an error", function()
        local ok, err = sandbox.validate("local foo = dontexist()")
        assert.is_false(ok)
        assert.matches("attempt to call global 'dontexist'", err, nil, true)
      end)

      it("returns false and error when input is lua that does not return a function", function()
        local ok, err = sandbox.validate("return 42")
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
        local ok, err = sandbox.validate("return function() end")
        assert.is_false(ok)
        assert.matches(sandbox.configuration.err_msg, err, nil, true)
      end)
    end)
  end)

  describe("sandbox.sandbox", function()
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
        sandbox.configuration:clear()
        assert.error(function() sandbox.sandbox("return 42") end)
      end)
    end)

    describe("untrusted_lua = 'on'", function()
      lazy_setup(function() setting = 'on' end)

      it("does not use sandbox", function()
        assert(sandbox.sandbox('return 42')())
        assert.spy(_sandbox).was_not.called()
      end)

      it("calls load with mode t (text only)", function()
        sandbox.sandbox("return 42")
        assert.spy(load_s).was.called()
        assert.equal("t", load_s.calls[1].vals[3])
      end)

      it("does not load binary strings (text only)", function()
        assert.error(function()
          sandbox.sandbox(string.dump(function() end))
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
          assert.same(_G.hello_world, sandbox.sandbox('return hello_world')())
        end)

        it("does not write _G", function()
          local r = sandbox.sandbox('hello_world = "foobar" return hello_world')()
          assert.same("foobar", r)
          assert.same("Hello World", _G.hello_world)
        end)

        it("does use an environment too", function()
          local env = { foo = 0}
          local fn = sandbox.parse([[
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
        sandbox.sandbox("return 42")
        assert.spy(_sandbox).was.called()
      end)

      it("calls load with mode t (text only)", function()
        sandbox.sandbox("return 42")
        assert.spy(load_s).was.called()
        assert.equal("t", load_s.calls[1].vals[3])
      end)

      it("does not load binary strings (text only)", function()
        assert.error(function()
          sandbox.sandbox(string.dump(function() end))
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
          if q == "" then return o end
          local h, r = q:match("([^%.]+)%.?(.*)")
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
            assert.same(find(m, _G), sandbox.sandbox(fmt("return %s", m))())
          end
        end)

        it("does not have access to anything else on the modules", function()
          for _, m in ipairs({ "foo.baz", "baz.foo", "baz.fuzz.question"}) do
            assert.is_nil(sandbox.sandbox(fmt("return %s", m))())
          end
        end)

        it("tables are read only", function()
          sandbox.sandbox([[ foo.bar.something = 'hello' ]])()
          assert.is_nil(_G.foo.bar.something)
        end)

        it("tables are unmutable on all levels", function()
          sandbox.sandbox([[ baz.fuzz.hallo = 'hello' ]])()
          assert.is_nil(_G.baz.fuzz.hallo)
        end)

        it("configuration.untrusted_lua_sandbox_environment is composable", function()
          local s_fizz = sandbox.sandbox([[ return fizz ]])()
          assert.same(_G.fizz, s_fizz)
        end)

        pending("opts.env is composable with sandbox_environment", function()
          local some_env = {
            foo = {
              something = { fun = function() end },
            }
          }
          local s_foo = sandbox.sandbox([[
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
                assert.equal(mock, sandbox.sandbox(fn)())

                finally(function() package.loaded[mod] = _o end)
            end
          end)

          it("cannot require anything else", function()
            local fn = sandbox.sandbox("return require('something-else')")
            local _, err = pcall(fn)
            assert.matches("require 'something-else' not allowed", err, nil, true)
          end)
        end)
      end)
    end)

  end)

  describe("sandbox.parse", function()
    for _, u in ipairs({'on', 'sandbox'}) do describe(("untrusted_lua = '%s'"):format(u), function()
      lazy_setup(function()
        _G.kong.configuration.untrusted_lua = u
      end)

      lazy_teardown(function()
        _G.kong.configuration = deep_copy(base_conf)
      end)

      it("returns a function when it gets code returning a function", function()
        local fn = sandbox.parse([[
          return function(something)
            return something
          end
        ]])
        assert.equal("function", type(fn))
        assert.equal("foobar", fn("foobar"))
      end)

      describe("errs with invalid input:", function()
        it("bad code", function()
          assert.error(function() sandbox.parse("foo bar baz") end)
        end)

        it("code that does not return a function", function()
          assert.error(function() sandbox.parse("return 42") end)
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
        assert.error(function() sandbox.parse("return 42") end)
      end)
    end)
  end)

end)
