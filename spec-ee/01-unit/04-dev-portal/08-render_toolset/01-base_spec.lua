local pl_tablex = require "pl.tablex"
local pl_stringx = require "pl.stringx"
local handler    = require "kong.portal.render_toolset.handler"


local function table_length(t)
  local count = 0
  for _ in pairs(t) do count = count + 1 end
  return count
end


describe("base", function()
  local base
  local snapshot

  before_each(function()
    snapshot = assert:snapshot()
  end)

  after_each(function()
    snapshot:revert()
  end)

  describe("table", function()
    describe("count", function()
      before_each(function()
        base = handler.new("base")
      end)

      it("can return the values of a table", function()
        local res = base()
                      :table({
                        ["key_x"] = "value_x",
                        ["key_y"] = "value_y",
                        ["key_z"] = "value_z"
                      })
                      :size()()

        assert.equals(res, 3)
      end)
    end)

    describe("values", function()
      before_each(function()
        base = handler.new("base")
      end)

      it("can return the values of a table", function()
        local res = base()
                      :table({
                        ["key_x"] = "value_x",
                        ["key_y"] = "value_y",
                        ["key_z"] = "value_z"
                      })
                      :values()()

        assert.equals(#res, 3)
        for i, v in ipairs(res) do
          assert(pl_stringx.startswith(v, "value"))
        end
      end)
    end)

    describe("keys", function()
      before_each(function()
        base = handler.new("base")
      end)

      it("can return the keys of a table", function()
        local res = base()
                      :table({
                        ["key_x"] = "value_x",
                        ["key_y"] = "value_y",
                        ["key_z"] = "value_z"
                      })
                      :keys()()

        assert.equals(#res, 3)
        for i, v in ipairs(res) do
          assert(pl_stringx.startswith(v, "key"))
        end
      end)
    end)

    describe("val", function()
      before_each(function()
        base = handler.new("base")
      end)

      -- it("can return value of table", function()
      --   local res = base()
      --                 :table({
      --                   ["key_x"] = "value_x",
      --                   ["key_y"] = "value_y",
      --                   ["key_z"] = "value_z"
      --                 })
      --                 :val("key_x")()

      --   assert.equals(res, "value_x")
      -- end)

      -- it("can return value of nested table", function()
      --   local res = base()
      --                 :table({
      --                   ["key_x"] = {
      --                     ["key_a"] = {
      --                       ["key_1"] = "thing"
      --                     }
      --                   },
      --                 })
      --                 :val("key_x.key_a.key_1")()

      --   assert.equals(res, "thing")
      -- end)

      it("can handle boolean value", function()
        local res = base()
                      :table({
                        ["key_x"] = {
                          ["key_a"] = {
                            ["key_1"] = false
                          }
                        },
                      })
                      :val("key_x.key_a.key_1")()

        assert.equals(res, false)
      end)
    end)

    describe("filter", function()
      before_each(function()
        base = handler.new("base")
      end)

      it("can filter table", function()
        local function compare_cb(k, v)
          if v == "value_x" then
            return true
          end
        end

        local res = base()
                      :table({
                        ["key_x"] = "value_x",
                        ["key_y"] = "value_y",
                        ["key_z"] = "value_z"
                      })
                      :filter(compare_cb)()

        assert.equals(res["key_x"], "value_x")
        assert.equals(table_length(res), 1)
      end)

      it("can filter table with outside arg in compare_cb", function()
        local function compare_cb(k, v, arg)
          if v == arg then
            return true
          end
        end

        local res = base()
                      :table({
                        ["key_x"] = "value_x",
                        ["key_y"] = "value_y",
                        ["key_z"] = "value_z"
                      })
                      :filter(compare_cb, "value_x")()

        assert.equals(res["key_x"], "value_x")
        assert.equals(table_length(res), 1)
      end)

      it("can filter array", function()
        local function compare_cb(_, item)
          if item == "a" then
            return true
          end
        end

        local res = base()
                      :table({ "a", "b", "c" })
                      :filter(compare_cb)()

        assert.equals(res[1], "a")
        assert.equals(#res, 1)
      end)

      it("can filter array with extra args", function()
        local function compare_cb(_, item, arg)
          if item == arg then
            return true
          end
        end

        local res = base()
                      :table({ "a", "b", "c" })
                      :filter(compare_cb, "b")()

        assert.equals(res[1], "b")
        assert.equals(#res, 1)
      end)
    end)

    describe("map", function()
      before_each(function()
        base = handler.new("base")
      end)

      it("can map table", function()
        local function map_cb(v)
          return v .. 'ABC'
        end

        local res = base()
                      :table({
                        ["key_x"] = "value_x",
                        ["key_y"] = "value_y",
                        ["key_z"] = "value_z"
                      })
                      :map(map_cb)()

        assert.equals(res["key_x"], "value_xABC")
        assert.equals(res["key_y"], "value_yABC")
        assert.equals(res["key_z"], "value_zABC")
      end)

      it("can map table with extra args", function()
        local function map_cb(v, str)
          return v .. str
        end

        local res = base()
                      :table({
                        ["key_x"] = "value_x",
                        ["key_y"] = "value_y",
                        ["key_z"] = "value_z"
                      })
                      :map(map_cb, 'ABC')()

        assert.equals(res["key_x"], "value_xABC")
        assert.equals(res["key_y"], "value_yABC")
        assert.equals(res["key_z"], "value_zABC")
      end)

      it("can map array", function()
        local function map_cb(v)
          return v .. 'ABC'
        end

        local res = base()
                      :table({
                        "value_x",
                        "value_y",
                        "value_z"
                      })
                      :map(map_cb)()

        assert.equals(res[1], "value_xABC")
        assert.equals(res[2], "value_yABC")
        assert.equals(res[3], "value_zABC")
      end)

      it("can map array with extra args", function()
        local function map_cb(v, str)
          return v .. str
        end

        local res = base()
                      :table({
                        "value_x",
                        "value_y",
                        "value_z"
                      })
                      :map(map_cb, 'ABC')()

        assert.equals(res[1], "value_xABC")
        assert.equals(res[2], "value_yABC")
        assert.equals(res[3], "value_zABC")
      end)
    end)

    describe("pairs", function()
      it("can iterate over table", function()
        local tbl = {
          ["key_x"] = "value_x",
          ["key_y"] = "value_y",
          ["key_z"] = "value_z"
        }
        local val_res = {}
        local key_res = {}
        for k, v in base():table(tbl):pairs() do
          table.insert(val_res, v)
          table.insert(key_res, k)
        end
        assert(pl_tablex.find(val_res, "value_x"), 1)
        assert(pl_tablex.find(key_res, "key_x"), 1)
        assert(pl_tablex.find(val_res, "value_y"), 1)
        assert(pl_tablex.find(key_res, "key_y"), 1)
        assert(pl_tablex.find(val_res, "value_z"), 1)
        assert(pl_tablex.find(key_res, "key_z"), 1)
      end)

      it("can iterate over list", function()
        local tbl = {
          "value_x",
          "value_y",
          "value_z"
        }
        local val_res = {}
        for i, v in base():table(tbl):pairs() do
          table.insert(val_res, v)
        end
        assert(pl_tablex.find(val_res, "value_x"), 1)
        assert(pl_tablex.find(val_res, "value_y"), 1)
        assert(pl_tablex.find(val_res, "value_z"), 1)
      end)
    end)

    describe("sortk", function()
      it("can sort over table by keys", function()
        local tbl = {
          ["key_z"] = "a",
          ["key_y"] = "c",
          ["key_x"] = "b",
        }

        local key_str = ""
        for k, v in base():table(tbl):sortk() do
          key_str = key_str .. k .. ","
        end

        assert.equals(key_str, "key_x,key_y,key_z,")
      end)

      it("can sort over table by keys with custom cb", function()
        local tbl = {
          ["key_z"] = "a",
          ["key_x"] = "b",
          ["key_y"] = "c",
        }

        local sort_cb = function(a, b)
          return a > b
        end

        local key_str = ""
        for k, v in base():table(tbl):sortk(sort_cb) do
          key_str = key_str .. k .. ","
        end

        assert.equals(key_str, "key_z,key_y,key_x,")
      end)
    end)


    describe("sortv", function()
      it("can sort over table by keys", function()
        local tbl = {
          ["a"] = "value_z",
          ["c"] = "value_y",
          ["b"] = "value_x",
        }

        local key_str = ""
        for k, v in base():table(tbl):sortv() do
          key_str = key_str .. v .. ","
        end

        assert.equals(key_str, "value_x,value_y,value_z,")
      end)

      it("can sort over table by keys with custom cb", function()
        local tbl = {
          ["a"] = "value_z",
          ["b"] = "value_x",
          ["c"] = "value_y",
        }

        local sort_cb = function(a, b)
          return a > b
        end

        local key_str = ""
        for k, v in base():table(tbl):sortv(sort_cb) do
          key_str = key_str .. v .. ","
        end

        assert.equals(key_str, "value_z,value_y,value_x,")
      end)
    end)


    describe("sub", function()
      it("can slice subset of list", function()
        local tbl = { 1, 2, 3, 4, 5 }

        local res = base():table(tbl):sub(1, 3)()
        assert.equals(3, #res)
        for i, v in ipairs(res) do
          assert.equals(i, v)
        end
      end)

      it("can slice negative subset of list", function()
        local tbl = { 1, 2, 3, 4, 5 }

        local res = base():table(tbl):sub(-2)()
        assert.equals(2, #res)
        assert.equals(res[1], 4)
        assert.equals(res[2], 5)
      end)
    end)
  end)

  describe("string", function()
    describe("upper", function()
      before_each(function()
        base = handler.new("base")
      end)

      it("can uppercase string", function()
        local res = base()
                      :string("dog")
                      :upper()()

        assert.equals(res, "DOG")
      end)
    end)

    describe("lower", function()
      before_each(function()
        base = handler.new("base")
      end)

      it("can uppercase string", function()
        local res = base()
                      :string("DOG")
                      :lower()()

        assert.equals(res, "dog")
      end)
    end)

    describe("reverse", function()
      before_each(function()
        base = handler.new("base")
      end)

      it("can reverse string", function()
        local res = base()
                      :string("dog")
                      :reverse()()

        assert.equals(res, "god")
      end)
    end)

    describe("gsub", function()
      before_each(function()
        base = handler.new("base")
      end)

      it("can replace all occurances string", function()
        local res = base()
                      :string("door")
                      :gsub("o", "O")()

        assert.equals(res, "dOOr")
      end)

      it("can replace a set ammount of occurances string", function()
        local res = base()
                      :string("door")
                      :gsub("o", "O", 1)()

        assert.equals(res, "dOor")
      end)

      it("can use a function to set replacement of occurances in string", function()
        local res = base()
                      :string("door")
                      :gsub("o", function(v)
                        return v .. "U"
                      end)()

        assert.equals(res, "doUoUr")
      end)
    end)

    describe("len", function()
      before_each(function()
        base = handler.new("base")
      end)

      it("can return length of string", function()
        local res = base()
                      :string("dog")
                      :len()()

        assert.equals(res, 3)
      end)
    end)

    describe("split", function()
      before_each(function()
        base = handler.new("base")
      end)

      it("can split string by delimiter", function()
        local res = base()
                      :string("d.o.g")
                      :split('.')()

        assert.equals(#res, 3)
      end)

      it("can split string by delimiter by length", function()
        local res = base()
                      :string("d.o.g")
                      :split('.', 2)()

        assert.equals(#res, 2)
      end)
    end)
  end)

  -- TODO: write boolean & number tests
end)
