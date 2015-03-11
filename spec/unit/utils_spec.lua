local utils = require "kong.tools.utils"
local constants = require "kong.constants"
local cjson = require "cjson"
local stringy = require "stringy"
require "lfs"

describe("Version #version", function()

  it("should match the right version", function()
    local rockspec_path
    for filename in lfs.dir("./") do
      if stringy.endswith(filename, "rockspec") then
        rockspec_path  = "./"..filename
        break
      end
    end

    if not rockspec_path then
      error("Can't find the rockspec file")
    end

    local file_content = utils.read_file(rockspec_path)
    local res = file_content:match("\"+[0-9.-]+[a-z]*[0-9-]*\"+")
    local extracted_version = res:sub(2, res:len() - 1)
    assert.are.same(constants.VERSION, extracted_version)
  end)

end)

describe("Utils #utils", function()

  describe("Table utils", function()
    it("should sort a table in ascending order by its keys without order set", function()
      local t = {
        [1] = "one",
        [3] = "three",
        [2] = "two"
      }

      local keyset = {}
      for k,v in utils.sort_table(t) do
        table.insert(keyset, k)
      end

      assert.are.same({1, 2, 3}, keyset)
    end)
    it("should sort a table in ascending order by its keys with ascending order set", function()
      local t = {
        [1] = "one",
        [3] = "three",
        [2] = "two"
      }

      local keyset = {}
      for k,v in utils.sort_table(t, utils.sort.ascending) do
        table.insert(keyset, k)
      end

      assert.are.same({1, 2, 3}, keyset)
    end)
    it("should sort a table in descending order by its keys with descending order set", function()
      local t = {
        [1] = "one",
        [3] = "three",
        [2] = "two"
      }

      local keyset = {}
      for k,v in utils.sort_table(t, utils.sort.descending) do
        table.insert(keyset, k)
      end

      assert.are.same({3, 2, 1}, keyset)
    end)
    it("should sort an array in ascending order by its keys without order set", function()
      local t = { 3, 1, 2 }

      local keyset = {}
      for k,v in utils.sort_table(t) do
        table.insert(keyset, k)
      end

      assert.are.same({1, 2, 3}, keyset)
    end)
    it("should sort an array in ascending order by its keys with ascending order set", function()
      local t = { 3, 1, 2 }

      local keyset = {}
      for k,v in utils.sort_table(t, utils.sort.ascending) do
        table.insert(keyset, k)
      end

      assert.are.same({1, 2, 3}, keyset)
    end)
    it("should sort an array in descending order by its keys with descending order set", function()
      local t = { 3, 1, 2 }

      local keyset = {}
      for k,v in utils.sort_table(t, utils.sort.descending) do
        table.insert(keyset, k)
      end

      assert.are.same({3, 2, 1}, keyset)
    end)
  end)

  describe("tables", function()

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
  end)
end)
