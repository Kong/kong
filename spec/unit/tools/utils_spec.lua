local utils = require "kong.tools.utils"

describe("Utils", function()

  describe("string", function()
    describe("random_string()", function()
      it("should return a random string", function()
        local first = utils.random_string()
        assert.truthy(first)
        assert.falsy(first:find("-"))

        local second = utils.random_string()
        assert.not_equal(first, second)
      end)
    end)

    describe("encode_args()", function()
      it("should encode a Lua table to a querystring", function()
        local str = utils.encode_args {
          foo = "bar",
          hello = "world"
        }
        assert.equal("foo=bar&hello=world", str)
      end)
      it("should encode multi-value query args", function()
        local str = utils.encode_args {
          foo = {"bar", "zoo"},
          hello = "world"
        }
        assert.equal("foo=bar&foo=zoo&hello=world", str)
      end)
      it("should percent-encode given values", function()
        local str = utils.encode_args {
          encode = {"abc|def", ",$@|`"}
        }
        assert.equal("encode=abc%7cdef&encode=%2c%24%40%7c%60", str)
      end)
      it("should percent-encode given query args keys", function()
        local str = utils.encode_args {
          ["hello world"] = "foo"
        }
        assert.equal("hello%20world=foo", str)
      end)
      it("should support Lua numbers", function()
        local str = utils.encode_args {
          a = 1,
          b = 2
        }
        assert.equal("a=1&b=2", str)
      end)
      it("should support a boolean argument", function()
        local str = utils.encode_args {
          a = true,
          b = 1
        }
        assert.equal("a&b=1", str)
      end)
      it("should ignore nil and false values", function()
        local str = utils.encode_args {
          a = nil,
          b = false
        }
        assert.equal("", str)
      end)
      it("should encode complex query args", function()
        local str = utils.encode_args {
          multiple = {"hello, world"},
          hello = "world",
          ignore  = false,
          ["multiple values"] = true
        }
        assert.equal("hello=world&multiple=hello%2c%20world&multiple%20values", str)
      end)
      it("should not percent-encode if given a `raw` option", function()
        -- this is useful for kong.tools.http_client
        local str = utils.encode_args({
          ["hello world"] = "foo, bar"
        }, true)
        assert.equal("hello world=foo, bar", str)
      end)
      -- while this method's purpose is to mimic 100% the behavior of ngx.encode_args,
      -- it is also used by Kong specs' http_client, to encode both querystrings and *bodies*.
      -- Hence, a `raw` parameter allows encoding for bodies.
      describe("raw", function()
        it("should not percent-encode values", function()
          local str = utils.encode_args({
            foo = "hello world"
          }, true)
          assert.equal("foo=hello world", str)
        end)
        it("should not percent-encode keys", function()
          local str = utils.encode_args({
            ["hello world"] = "foo"
          }, true)
          assert.equal("hello world=foo", str)
        end)
        it("should plainly include true and false values", function()
          local str = utils.encode_args({
            a = true,
            b = false
          }, true)
          assert.equal("a=true&b=false", str)
        end)
      end)
    end)
  end)

  describe("table", function()
    describe("table_size()", function()
      it("should return the size of a table", function()
        assert.are.same(0, utils.table_size(nil))
        assert.are.same(0, utils.table_size({}))
        assert.are.same(1, utils.table_size({ foo = "bar" }))
        assert.are.same(2, utils.table_size({ foo = "bar", bar = "baz" }))
        assert.are.same(2, utils.table_size({ "foo", "bar" }))
      end)
    end)

    describe("table_contains()", function()
      it("should return false if a value is not contained in a nil table", function()
        assert.False(utils.table_contains(nil, "foo"))
      end)
      it("should return true if a value is contained in a table", function()
        local t = { foo = "hello", bar = "world" }
        assert.True(utils.table_contains(t, "hello"))
      end)
      it("should return false if a value is not contained in a table", function()
        local t = { foo = "hello", bar = "world" }
        assert.False(utils.table_contains(t, "foo"))
      end)
    end)

    describe("is_array()", function()
      it("should know when an array ", function()
        assert.True(utils.is_array({ "a", "b", "c", "d" }))
        assert.True(utils.is_array({ ["1"] = "a", ["2"] = "b", ["3"] = "c", ["4"] = "d" }))
        assert.False(utils.is_array({ "a", "b", "c", foo = "d" }))
        assert.False(utils.is_array())
        assert.False(utils.is_array(false))
        assert.False(utils.is_array(true))
      end)
    end)

    describe("add_error()", function()
      local add_error = utils.add_error

      it("should create a table if given `errors` is nil", function()
        assert.same({hello = "world"}, add_error(nil, "hello", "world"))
      end)
      it("should add a key/value when the key does not exists", function()
        local errors = {hello = "world"}
        assert.same({
          hello = "world",
          foo = "bar"
        }, add_error(errors, "foo", "bar"))
      end)
      it("should transform previous values to a list if the same key is given again", function()
        local e = nil -- initialize for luacheck
        e = add_error(e, "key1", "value1")
        e = add_error(e, "key2", "value2")
        assert.same({key1 = "value1", key2 = "value2"}, e)

        e = add_error(e, "key1", "value3")
        e = add_error(e, "key1", "value4")
        assert.same({key1 = {"value1", "value3", "value4"}, key2 = "value2"}, e)

        e = add_error(e, "key1", "value5")
        e = add_error(e, "key1", "value6")
        e = add_error(e, "key2", "value7")
        assert.same({key1 = {"value1", "value3", "value4", "value5", "value6"}, key2 = {"value2", "value7"}}, e)
      end)
      it("should also list tables pushed as errors", function()
        local e = nil -- initialize for luacheck
        e = add_error(e, "key1", "value1")
        e = add_error(e, "key2", "value2")
        e = add_error(e, "key1", "value3")
        e = add_error(e, "key1", "value4")

        e = add_error(e, "keyO", {message = "some error"})
        e = add_error(e, "keyO", {message = "another"})

        assert.same({
          key1 = {"value1", "value3", "value4"},
          key2 = "value2",
          keyO = {{message = "some error"}, {message = "another"}}
        }, e)
      end)
    end)

    describe("load_module_if_exists()", function()
      it("should return false if the module does not exist", function()
        local loaded, mod
        assert.has_no.errors(function()
          loaded, mod = utils.load_module_if_exists("kong.does.not.exist")
        end)
        assert.False(loaded)
        assert.falsy(mod)
      end)
      it("should throw an error if the module is invalid", function()
        local loaded, mod
        assert.has.errors(function()
          loaded, mod = utils.load_module_if_exists("spec.unit.fixtures.invalid-module")
        end)
        assert.falsy(loaded)
        assert.falsy(mod)
      end)
      it("should load a module if it was found and valid", function()
        local loaded, mod
        assert.has_no.errors(function()
          loaded, mod = utils.load_module_if_exists("spec.unit.fixtures.valid-module")
        end)
        assert.True(loaded)
        assert.truthy(mod)
        assert.are.same("All your base are belong to us.", mod.exposed)
      end)
    end)
  end)
end)
