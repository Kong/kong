local utils = require "kong.tools.utils"

describe("Utils", function()

  describe("strings", function()
    local first = utils.random_string()
    assert.truthy(first)
    assert.falsy(first:find("-"))
    local second = utils.random_string()
    assert.falsy(first == second)
  end)

  describe("tables", function()
    describe("#table_size()", function()

      it("should return the size of a table", function()
        assert.are.same(0, utils.table_size({}))
        assert.are.same(1, utils.table_size({ foo = "bar" }))
        assert.are.same(2, utils.table_size({ foo = "bar", bar = "baz" }))
        assert.are.same(2, utils.table_size({ "foo", "bar" }))
      end)

    end)

    describe("#table_contains()", function()

      it("should return true is a value is contained in a table", function()
        local t = { foo = "hello", bar = "world" }
        assert.True(utils.table_contains(t, "hello"))
      end)

      it("should return true is a value is not contained in a table", function()
        local t = { foo = "hello", bar = "world" }
        assert.False(utils.table_contains(t, "foo"))
      end)

    end)

    describe("#is_array()", function()

      it("should know when an array ", function()
        assert.True(utils.is_array({ "a", "b", "c", "d" }))
        assert.True(utils.is_array({ ["1"] = "a", ["2"] = "b", ["3"] = "c", ["4"] = "d" }))
        assert.False(utils.is_array({ "a", "b", "c", foo = "d" }))
      end)

    end)

    describe("#add_error()", function()

      it("should create a table if given `errors` is nil", function()
        assert.are.same({ hello = "world" }, utils.add_error(nil, "hello", "world"))
      end)

      it("should add a key/value when given `errors` already exists", function()
        local errors = { hello = "world" }
        assert.are.same({
          hello = "world",
          foo = "bar"
        }, utils.add_error(errors, "foo", "bar"))
      end)

      it("should create a list if the same key is given twice", function()
        local errors = { hello = "world" }
        assert.are.same({
          hello = {"world", "universe"}
        }, utils.add_error(errors, "hello", "universe"))
      end)

    end)

    describe("#load_module_if_exists()", function()

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
