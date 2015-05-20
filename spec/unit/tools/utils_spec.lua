local utils = require "kong.tools.utils"

describe("Utils", function()
  describe("tables", function()
    describe("#sort_table_iter()", function()

      it("should sort a table in ascending order by its keys without order set", function()
        local t = { [1] = "one", [3] = "three", [2] = "two" }
        local keyset = {}
        for k,v in utils.sort_table_iter(t) do
          table.insert(keyset, k)
        end

        assert.are.same({1, 2, 3}, keyset)
      end)

      it("should sort a table in ascending order by its keys with ascending order set", function()
        local t = { [1] = "one", [3] = "three", [2] = "two" }
        local keyset = {}
        for k,v in utils.sort_table_iter(t, utils.sort.ascending) do
          table.insert(keyset, k)
        end

        assert.are.same({1, 2, 3}, keyset)
      end)

      it("should sort a table in descending order by its keys with descending order set", function()
        local t = { [1] = "one", [3] = "three", [2] = "two" }
        local keyset = {}
        for k,v in utils.sort_table_iter(t, utils.sort.descending) do
          table.insert(keyset, k)
        end

        assert.are.same({3, 2, 1}, keyset)
      end)

      it("should sort an array in ascending order by its keys without order set", function()
        local t = { 3, 1, 2 }
        local keyset = {}
        for k,v in utils.sort_table_iter(t) do
          table.insert(keyset, k)
        end

        assert.are.same({1, 2, 3}, keyset)
      end)

      it("should sort an array in ascending order by its keys with ascending order set", function()
        local t = { 3, 1, 2 }
        local keyset = {}
        for k,v in utils.sort_table_iter(t, utils.sort.ascending) do
          table.insert(keyset, k)
        end

        assert.are.same({1, 2, 3}, keyset)
      end)

      it("should sort an array in descending order by its keys with descending order set", function()
        local t = { 3, 1, 2 }
        local keyset = {}
        for k,v in utils.sort_table_iter(t, utils.sort.descending) do
          table.insert(keyset, k)
        end

        assert.are.same({3, 2, 1}, keyset)
      end)

    end)

    describe("#is_empty()", function()

      it("should return true for empty table, false otherwise", function()
        assert.True(utils.is_empty({}))
        assert.is_not_true(utils.is_empty({ foo = "bar" }))
        assert.is_not_true(utils.is_empty({ "foo", "bar" }))
      end)

    end)

    describe("#table_size()", function()

      it("should return the size of a table", function()
        assert.are.same(0, utils.table_size({}))
        assert.are.same(1, utils.table_size({ foo = "bar" }))
        assert.are.same(2, utils.table_size({ foo = "bar", bar = "baz" }))
        assert.are.same(2, utils.table_size({ "foo", "bar" }))
      end)

    end)

    describe("#reverse_table()", function()

      it("should reverse an array", function()
        local arr = { "a", "b", "c", "d" }
        assert.are.same({ "d", "c", "b", "a" }, utils.reverse_table(arr))
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
          loaded, mod = utils.load_module_if_exists("spec.fixtures.invalid-module")
        end)
        assert.falsy(loaded)
        assert.falsy(mod)
      end)

      it("should load a module if it was found and valid", function()
        local loaded, mod
        assert.has_no.errors(function()
          loaded, mod = utils.load_module_if_exists("spec.fixtures.valid-module")
        end)
        assert.True(loaded)
        assert.truthy(mod)
        assert.are.same("All your base are belong to us.", mod.exposed)
      end)

    end)
  end)
end)
