local Schema = require "kong.db.schema"
local cjson  = require "cjson"


local luacov_ok = pcall(require, "luacov")
if luacov_ok then
  local busted_it = it
  -- luacheck: globals it
  it = function(desc, fn)
    busted_it(desc, function()
      local luacov = require("luacov")
      luacov.init()
      fn()
      luacov.save_stats()
    end)
  end
end


describe("schema", function()
  local uuid_pattern = "^" .. ("%x"):rep(8) .. "%-" .. ("%x"):rep(4) .. "%-"
                           .. ("%x"):rep(4) .. "%-" .. ("%x"):rep(4) .. "%-"
                           .. ("%x"):rep(12) .. "$"

  local function check_all_types_covered(fields)
    local covered = {}
    for _, item in ipairs(fields) do
      local field = item[next(item)]
      covered[field.type] = true
    end
    covered["foreign"] = true
    for name, _ in pairs(Schema.valid_types) do
      assert.truthy(covered[name], "type '" .. name .. "' not covered")
    end
  end

  describe("construction", function()

    it("fails if no definition is given", function()
      local Test, err = Schema.new()
      assert.falsy(Test)
      assert.string(err)
    end)

    it("fails if schema fields are not defined", function()
      local Test, err = Schema.new({ fields = nil })
      assert.falsy(Test)
      assert.string(err)
    end)


    it("fails on invalid foreign reference", function()
      local Test, err = Schema.new({
        fields = {
          { f = { type = "foreign", reference = "invalid_reference" } },
          { b = { type = "number" }, },
          { c = { type = "number" }, },
        }
      })
      assert.falsy(Test)
      assert.match("invalid_reference", err)
    end)

  end)

  describe("validate", function()

    it("orders validators", function()
      local validators_len = 0
      local validators_order_len = 0

      for _ in pairs(Schema.validators) do
        validators_len = validators_len + 1
      end

      for _ in pairs(Schema.validators_order) do
        validators_order_len = validators_order_len + 1
      end

      assert.equal(validators_len, validators_order_len)
    end)

    it("fails if given no input", function()
      local Test = Schema.new({ fields = {} })
      assert.has_error(function()
        Test:validate(nil)
      end)
    end)

    it("fails if given a bad field type", function()
      local Test = Schema.new({
        fields = {
          { foo = { type = "typo" }, },
        }
      })
      assert.falsy(Test:validate({ foo = "foo" }))
    end)

    it("validates a range with 'between'", function()
      local Test = Schema.new({
        fields = {
          { a_number = { type = "number", between = { 10, 20 } } }
        }
      })
      assert.truthy(Test:validate({ a_number = 15 }))
      assert.truthy(Test:validate({ a_number = 10 }))
      assert.truthy(Test:validate({ a_number = 20 }))
      assert.falsy(Test:validate({ a_number = 9 }))
      assert.falsy(Test:validate({ a_number = 21 }))
      assert.falsy(Test:validate({ a_number = "wat" }))
    end)

    it("forces a value with 'eq'", function()
      local Test = Schema.new({
        fields = {
          { a_number = { type = "number", eq = 9 } }
        }
      })
      assert.truthy(Test:validate({ a_number = 9 }))
      assert.falsy(Test:validate({ a_number = 8 }))
      assert.falsy(Test:validate({ a_number = "wat" }))
    end)

    it("forces a value with 'gt'", function()
      local Test = Schema.new({
        fields = {
          { a_number = { type = "number", gt = 5 } }
        }
      })
      assert.truthy(Test:validate({ a_number = 6 }))
      assert.falsy(Test:validate({ a_number = 5 }))
      assert.falsy(Test:validate({ a_number = 4 }))
      assert.falsy(Test:validate({ a_number = "wat" }))
    end)

    it("validates arrays with 'contains'", function()
      local Test = Schema.new({
        fields = {
          { pirate = { type = "array",
                       elements = { type = "string" },
                       contains = "arrr",
                     },
          }
        }
      })
      assert.truthy(Test:validate({ pirate = { "aye", "arrr", "treasure" } }))
      assert.falsy(Test:validate({ pirate = { "let's do our taxes", "please" } }))
      assert.falsy(Test:validate({ pirate = {} }))
    end)

    it("makes sure all types run validators", function()
      local num = { type = "number" }
      local tests = {
        { { type = "array", elements = num, len_eq = 2 },
          { 10, 20, 30 } },
        { { type = "set", elements = num, len_eq = 2 },
          { 10, 20, 30 } },
        { { type = "string", len_eq = 2 },
          "foo" },
        { { type = "number", between = { 1, 3 } },
          4 },
        { { type = "integer", between = { 1, 3 } },
          4 },
        { { type = "map" },     -- no map-specific validators
          "fail" },
        { { type = "record" },  -- no record-specific validators
          "fail" },
        { { type = "boolean" }, -- no boolean-specific validators
          "fail" },
        { { type = "function" },
          "fail" },
      }

      local covered_check = {}
      for i, test in pairs(tests) do
        table.insert(covered_check, { ["a"..tostring(i)] = test[1] })
        local Test = Schema.new({
          fields = {
            { x = test[1] }
          }
        })
        local ret, errs = Test:validate({ x = test[2] })
        local case_msg = "Error case: "..test[1].type
        assert.falsy(ret, case_msg)
        assert.truthy(errs["x"], case_msg)
      end
      check_all_types_covered(covered_check)
    end)

    it("validates a pattern with 'match'", function()
      local Test = Schema.new({
        fields = {
          { f = { type = "string", match = "^%u+$" } }
        }
      })
      assert.truthy(Test:validate({ f = "HELLO" }))
      assert.truthy(Test:validate({ f = "O" }))
      assert.falsy(Test:validate({ f = "" }))
      assert.falsy(Test:validate({ f = 1 }))
    end)

    it("validates an anti-pattern with 'not_match'", function()
      local Test = Schema.new({
        fields = {
          { f = { type = "string", not_match = "^%u+$" } }
        }
      })
      assert.truthy(Test:validate({ f = "hello" }))
      assert.truthy(Test:validate({ f = "o" }))
      assert.falsy(Test:validate({ f = "HELLO" }))
      assert.falsy(Test:validate({ f = 1 }))
    end)

    it("validates one pattern among many with 'match_any'", function()
      local Test = Schema.new({
        fields = {
          { f = {
              type = "string",
              match_any = {
                patterns = { "^hello", "world$" },
              }
            }
          }
        }
      })
      assert.truthy(Test:validate({ f = "hello Earth" }))
      assert.truthy(Test:validate({ f = "goodbye world" }))
      assert.falsy(Test:validate({ f = "hi universe" }))
      assert.falsy(Test:validate({ f = 1 }))
    end)

    it("'match_any' produces custom messages", function()
      local Test2 = Schema.new({
        fields = {
          { f = {
              type = "string",
              match_any = {
                patterns = { "^hello", "world$" },
                err = "custom message",
              }
            }
          }
        }
      })
      local ok, err = Test2:validate({ f = "hi universe" })
      assert.falsy(ok)
      assert.same({ f = "custom message" }, err)
    end)

    it("validates all patterns in 'match_all'", function()
      local Test = Schema.new({
        fields = {
          { f = {
              type = "string",
              match_all = {
                { pattern = "^hello" },
                { pattern = "world$" },
              }
            }
          }
        }
      })
      assert.truthy(Test:validate({ f = "helloworld" }))
      assert.truthy(Test:validate({ f = "hello crazy world" }))
      assert.falsy(Test:validate({ f = "hello universe" }))
      assert.falsy(Test:validate({ f = "goodbye world" }))
      assert.falsy(Test:validate({ f = "hi universe" }))
      assert.falsy(Test:validate({ f = 1 }))
    end)

    it("'match_all' produces custom messages", function()
      local Test2 = Schema.new({
        fields = {
          { f = {
              type = "string",
              match_all = {
                { pattern = "^hello", err = "error 1" },
                { pattern = "world$", err = "error 2" },
              }
            }
          }
        }
      })
      local ok, err = Test2:validate({ f = "hi universe" })
      assert.falsy(ok)
      assert.same({ f = "error 1" }, err)
      ok, err = Test2:validate({ f = "hello universe" })
      assert.falsy(ok)
      assert.same({ f = "error 2" }, err)
    end)

    it("validates all anti-patterns in 'match_none'", function()
      local Test = Schema.new({
        fields = {
          { f = {
              type = "string",
              match_none = {
                { pattern = "^hello" },
                { pattern = "world$" },
              }
            }
          }
        }
      })
      assert.falsy(Test:validate({ f = "helloworld" }))
      assert.falsy(Test:validate({ f = "hello crazy world" }))
      assert.falsy(Test:validate({ f = "hello universe" }))
      assert.falsy(Test:validate({ f = "goodbye world" }))
      assert.truthy(Test:validate({ f = "hi universe" }))
    end)

    it("'match_none' produces custom messages", function()
      local Test2 = Schema.new({
        fields = {
          { f = {
              type = "string",
              match_none = {
                { pattern = "^hello", err = "error 1" },
                { pattern = "world$", err = "error 2" },
              }
            }
          }
        }
      })
      local ok, err = Test2:validate({ f = "hello universe" })
      assert.falsy(ok)
      assert.same({ f = "error 1" }, err)
      ok, err = Test2:validate({ f = "goodbye world" })
      assert.falsy(ok)
      assert.same({ f = "error 2" }, err)
    end)

    it("validates an array length with 'len_eq'", function()
      local Test = Schema.new({
        fields = {
          {
            arr = {
              type = "array",
              elements = { type = "number" },
              len_eq = 3
            },
          },
        }
      })
      assert.truthy(Test:validate({ arr = { 1, 2, 3 }}))
      assert.falsy(Test:validate({ arr = { 1 }}))
      assert.falsy(Test:validate({ arr = { 1, 2, 3, 4 }}))
    end)

    it("validates an array and a set is sequentical", function()
      local Test = Schema.new({
        fields = {
          { set = { type = "set",   elements = { type = "number" } } },
          { arr = { type = "array", elements = { type = "number" } } },
        }
      })

      local tests = {
        [{}]                       = true,
        [{ 1 }]                    = true,
        [{ nil, 1 }]               = false,
        [{ 1, 2, 3 }]              = true,
        [{ 1, 2, 3, nil }]         = true,
        [{ 1, 2, 3, nil, 4, nil }] = false
      }

      for t, result in pairs(tests) do
        local fields = Test:process_auto_fields({
          arr = t,
          set = t,
        })

        if result then
          assert.truthy(Test:validate(fields))
        else
          assert.falsy(Test:validate(fields))
        end
      end
    end)

    it("validates a set length with 'len_eq'", function()
      local Test = Schema.new({
        fields = {
          {
            set = {
              type = "set",
              elements = { type = "number" },
              len_eq = 3
            },
          }
        }
      })
      local function check(set)
        set = Test:process_auto_fields(set)
        return Test:validate(set)
      end
      assert.truthy(check({ set = { 4, 5, 6 }}))
      assert.truthy(check({ set = { 4, 5, 6, 4 }}))
      assert.falsy(check({ set = { 4, 4, 4 }}))
      assert.falsy(check({ set = { 4, 5 }}))
    end)

    it("validates a string length with 'len_min'", function()
      local Test = Schema.new({
        fields = {
          { s = { type = "string", len_min = 1 }, },
        }
      })
      assert.truthy(Test:validate({ s = "A" }))
      assert.truthy(Test:validate({ s = "AAAAA" }))
      assert.falsy(Test:validate({ s = "" }))
    end)

    it("strings cannot be empty unless said otherwise", function()
      local Test = Schema.new({
        fields = {
          { a = { type = "string" }, },
          { b = { type = "string", len_min = 0 }, },
        }
      })
      assert.truthy(Test:validate({ a = "AA", b = "AA" }))
      assert.truthy(Test:validate({ a = "A", b = "A" }))
      assert.truthy(Test:validate({ a = "A", b = "" }))
      local ok, errs = Test:validate({ a = "", b = "" })
      assert.falsy(ok)
      assert.string(errs["a"])
      assert.falsy(errs["b"])
    end)

    it("validates a string length with 'len_max'", function()
      local Test = Schema.new({
        fields = {
          { s = { type = "string", len_min = 1 }, },
        }
      })
      assert.truthy(Test:validate({ s = "A" }))
      assert.truthy(Test:validate({ s = "AAAAA" }))
      assert.falsy(Test:validate({ s = "" }))
    end)

    it("validates a timestamp with 'timestamp'", function()
      local Test = Schema.new({
        fields = {
          { a_number = { type = "number", timestamp = true } }
        }
      })
      for _, n in ipairs({ 1, 1234567890, 9876543210 }) do
        assert.truthy(Test:validate({ a_number = n }))
      end
      for _, n in ipairs({ -1, 0, "wat" }) do
        assert.falsy(Test:validate({ a_number = n }))
      end
    end)

    it("validates the shape of UUIDs with 'uuid'", function()
      local Test = Schema.new({
        fields = {
          { f = { type = "string", uuid = true } }
        }
      })

      local tests = {
        -- correct
        { "truthy", "cbb297c0-a956-486d-ad1d-f9b42df9465a" },
        -- invalid variant, but accepts
        { "truthy", "cbb297c0-a956-486d-dd1d-f9b42df9465a" },
        -- "null" UUID
        { "truthy", "00000000-0000-0000-0000-000000000000" },
        -- incorrect characters
        { "falsy", "cbb297c0-a956-486d-ad1d-f9bZZZZZZZZZ" },
        -- no dashes
        { "falsy", "cbb297c0a956486dad1df9b42df9465a" },
      }
      for _, test in ipairs(tests) do
        assert[test[1]](Test:validate({ f = test[2] }))
      end
    end)

    it("ensures an array is a table", function()
      local Test = Schema.new({
        fields = {
          { f = { type = "array", elements = { type = "string" } } }
        }
      })
      assert.truthy(Test:validate({ f = {} }))
      assert.falsy(Test:validate({ f = "foo" }))
    end)

    it("requires an array schema to have `elements`", function()
      local Test = Schema.new({
        fields = {
          { f = { type = "array" } }
        }
      })
      assert.falsy(Test:validate({ f = {} }))
    end)

    it("validates array elements", function()
      local Test = Schema.new({
        fields = {
          { f = { type = "array", elements = { type = "number" } } }
        }
      })
      assert.truthy(Test:validate({ f = {} }))
      assert.truthy(Test:validate({ f = {1} }))
      assert.truthy(Test:validate({ f = {1, -1} }))
      assert.falsy(Test:validate({ f = {"hello"} }))
      assert.falsy(Test:validate({ f = {1, 2, "foo"} }))
    end)

    it("validates rules in array elements", function()
      local Test = Schema.new({
        fields = {
          {
            f = {
              type = "array",
              elements = {
                type = "string",
                one_of = { "foo", "bar", "baz" }
              }
            }
          }
        }
      })
      assert.truthy(Test:validate({ f = {} }))
      assert.truthy(Test:validate({ f = {"foo"} }))
      assert.truthy(Test:validate({ f = {"baz", "foo"} }))
      assert.falsy(Test:validate({ f = {"hello"} }))
      assert.falsy(Test:validate({ f = {"foo", "hello", "foo"} }))
    end)

    it("ensures a set is a table", function()
      local Test = Schema.new({
        fields = {
          { f = { type = "set", elements = { type = "string" } } }
        }
      })
      assert.truthy(Test:validate({ f = {} }))
      assert.falsy(Test:validate({ f = "foo" }))
    end)

    it("requires an set schema to have `elements`", function()
      local Test = Schema.new({
        fields = {
          { f = { type = "set" } }
        }
      })
      assert.falsy(Test:validate({ f = {} }))
    end)

    it("validates set elements", function()
      local Test = Schema.new({
        fields = {
          { f = { type = "set", elements = { type = "number" } } }
        }
      })
      assert.truthy(Test:validate({ f = {} }))
      assert.truthy(Test:validate({ f = {1} }))
      assert.truthy(Test:validate({ f = {1, -1} }))
      assert.falsy(Test:validate({ f = {"hello"} }))
      assert.falsy(Test:validate({ f = {1, 2, "foo"} }))
    end)

    it("validates set elements", function()
      local Test = Schema.new({
        fields = {
          { f = { type = "set", elements = { type = "number" } } }
        }
      })
      assert.truthy(Test:validate({ f = {} }))
      assert.truthy(Test:validate({ f = {1} }))
      assert.truthy(Test:validate({ f = {1, -1} }))
      assert.falsy(Test:validate({ f = {"hello"} }))
      assert.falsy(Test:validate({ f = {1, 2, "foo"} }))
    end)

    it("ensures a map is a table", function()
      local Test = Schema.new({
        fields = {
          {
            f = {
              type = "map",
              keys = { type = "string" },
              values = { type = "string" },
            }
          }
        }
      })
      assert.truthy(Test:validate({ f = {} }))
      assert.falsy(Test:validate({ f = "foo" }))
    end)

    it("fails with a map without `keys` and `values`", function()
      local Test = Schema.new({
        fields = {
          { f = { type = "map" } }
        }
      })
      assert.falsy(Test:validate({ f = {} }))
    end)

    it("fails with a map without `values`", function()
      local Test = Schema.new({
        fields = {
          { f = { type = "map", keys = { type = "string" } } }
        }
      })
      assert.falsy(Test:validate({ f = {} }))
    end)

    it("fails with a map without `keys`", function()
      local Test = Schema.new({
        fields = {
          { f = { type = "map", values = { type = "string" } } }
        }
      })
      assert.falsy(Test:validate({ f = {} }))
    end)

    it("accepts a map with `keys` and `values`", function()
      local Test = Schema.new({
        fields = {
          {
            f = {
              type = "map",
              keys = { type = "string" },
              values = { type = "string" },
            }
          }
        }
      })
      assert.truthy(Test:validate({ f = {} }))
    end)

   it("validates map elements", function()
      local Test = Schema.new({
        fields = {
          {
            f = {
              type = "map",
              keys = { type = "string" },
              values = { type = "number" },
            }
          }
        }
      })
      assert.truthy(Test:validate({ f = { foo = 2 } }))
      assert.falsy(Test:validate({ f = { [2] = 2 } }))
      assert.falsy(Test:validate({ f = { [2] = "foo" } }))
      assert.falsy(Test:validate({ f = { foo = "foo" } }))
      assert.truthy(Test:validate({ f = { bar = 3, foo = 2 } }))
      assert.falsy(Test:validate({ f = { bar = 3, [2] = 2 } }))
      assert.falsy(Test:validate({ f = { bar = 3, [2] = "foo" } }))
      assert.falsy(Test:validate({ f = { bar = 3, foo = "foo" } }))
    end)

    it("ensures a record is a table", function()
      local Test = Schema.new({
        fields = {
          {
            f = {
              type = "record",
              fields = { r = { type = "string" } },
            }
          }
        }
      })
      assert.truthy(Test:validate({ f = {} }))
      assert.falsy(Test:validate({ f = "foo" }))
    end)

    it("requires a record to have `fields`", function()
      local Test = Schema.new({
        fields = {
          { f = { type = "record" } }
        }
      })
      assert.falsy(Test:validate({ f = {} }))
      local Test = Schema.new({
        fields = {
          {
            f = {
              type = "record",
              fields = {},
            }
          }
        }
      })
      assert.truthy(Test:validate({ f = {} }))
    end)

   it("validates record elements", function()
      local Test = Schema.new({
        fields = {
          {
            f = {
              type = "record",
              fields = {
                { a = { type = "string" }, },
                { b = { type = "number" }, },
              },
            }
          }
        }
      })
      assert.truthy(Test:validate({ f = { a = "foo" } }))
      assert.truthy(Test:validate({ f = { b = 42 } }))
      assert.truthy(Test:validate({ f = { a = "foo", b = 42 } }))
      assert.falsy(Test:validate({ f = { a = 2 } }))
      assert.falsy(Test:validate({ f = { b = "foo" } }))
      assert.falsy(Test:validate({ f = { a = 2, b = "foo" } }))
    end)

   it("validates nested records", function()
      local Test = Schema.new({
        fields = {
          { f = {
              type = "record",
              fields = {
                { r = {
                    type = "record",
                    fields = {
                      { a = { type = "string" } },
                      { b = { type = "number" } } }}}}}}}})
      assert.truthy(Test:validate({ f = { r = { a = "foo" }}}))
      assert.truthy(Test:validate({ f = { r = { b = 42 }}}))
      assert.truthy(Test:validate({ f = { r = { a = "foo", b = 42 }}}))
      assert.falsy(Test:validate({ f = { r = { a = 2 }}}))
      assert.falsy(Test:validate({ f = { r = { b = "foo" }}}))
      assert.falsy(Test:validate({ f = { r = { a = 2, b = "foo" }}}))
    end)

    it("validates an integer", function()
      local Test = Schema.new({
        fields = {
          { f = { type = "integer" } }
        }
      })
      assert.truthy(Test:validate({ f = 123 }))
      assert.truthy(Test:validate({ f = 0 }))
      assert.truthy(Test:validate({ f = -123 }))
      assert.falsy(Test:validate({ f = 0.5 }))
      assert.falsy(Test:validate({ f = -0.5 }))
      assert.falsy(Test:validate({ f = 1/0 }))
      assert.falsy(Test:validate({ f = -1/0 }))
      assert.falsy(Test:validate({ f = math.huge }))
      assert.falsy(Test:validate({ f = "123" }))
      assert.falsy(Test:validate({ f = "foo" }))
    end)

    it("validates a number", function()
      local Test = Schema.new({
        fields = {
          { f = { type = "number" } }
        }
      })
      assert.truthy(Test:validate({ f = 123 }))
      assert.truthy(Test:validate({ f = 0 }))
      assert.truthy(Test:validate({ f = -123 }))
      assert.truthy(Test:validate({ f = 0.5 }))
      assert.truthy(Test:validate({ f = -0.5 }))
      assert.truthy(Test:validate({ f = 1/0 }))
      assert.truthy(Test:validate({ f = -1/0 }))
      assert.truthy(Test:validate({ f = math.huge }))
      assert.falsy(Test:validate({ f = "123" }))
      assert.falsy(Test:validate({ f = "foo" }))
    end)

    it("validates a boolean", function()
      local Test = Schema.new({
        fields = {
          { f = { type = "boolean" } }
        }
      })
      assert.truthy(Test:validate({ f = true }))
      assert.truthy(Test:validate({ f = false }))
      assert.falsy(Test:validate({ f = 0 }))
      assert.falsy(Test:validate({ f = 1 }))
      assert.falsy(Test:validate({ f = "true" }))
      assert.falsy(Test:validate({ f = "false" }))
      assert.falsy(Test:validate({ f = "foo" }))
    end)

    it("fails on unknown fields", function()
      local Test = Schema.new({
        fields = {
          { f = { type = "number", required = true } }
        }
      })
      assert.falsy(Test:validate({ k = "wat" }))
    end)

    local function run_custom_check_producing_error(error)
      local Test = Schema.new({
        fields = {
          { password = { type = "string" }, },
          { confirm_password = { type = "string" }, },
        }
      })
      local check = function(fields)
        if fields.password ~= fields.confirm_password then
          return nil, error
        end
        return true
      end

      Test.check = check
      local data, errs = Test:validate({
        password = "123456",
        confirm_password = "123456",
      })
      Test.check = nil
      assert.is_nil(errs)
      assert.truthy(data)

      Test.check = check
      local entity_errs
      data, errs, entity_errs = Test:validate({
        password = "123456",
        confirm_password = "1234",
      })
      Test.check = nil
      assert.falsy(data)
      return errs, entity_errs
    end

    it("runs a custom check with string error", function()
      local errors = run_custom_check_producing_error(
        "passwords must match"
      )
      assert.same({ ["@entity"] = { "passwords must match" } }, errors)
    end)

    it("runs a custom check with table keyed error", function()
      local errors = run_custom_check_producing_error(
        { password = "passwords must match" }
      )
      assert.same({ password = "passwords must match" }, errors)
    end)

    it("runs a custom check with table numbered error", function()
      local errors = run_custom_check_producing_error(
        { "passwords must match", "a second error" }
      )
      assert.same({
        ["@entity"] = {"passwords must match", "a second error" }
      }, errors)
    end)

    it("runs a custom check with no message", function()
      local errors = run_custom_check_producing_error(nil)
      -- still produces a default message
      assert.same({
        ["@entity"] = { "entity check failed" }
      }, errors)
    end)

    it("merges field and custom checks", function()
      local Test = Schema.new({
        fields = {
          { fail1 = { type = "string", match = "aaa" } },
          { fail2 = { type = "string", match = "bbb" } },
        },
        check = function()
          return nil, {
            [1] = "a generic check error",
            [2] = "another generic check error",
            fail2 = "my own field error",
          }
        end,
      })
      local data, errs = Test:validate({
        fail1 = "ccc",
        fail2 = "ddd",
      })
      assert.falsy(data)
      assert.same("a generic check error", errs["@entity"][1])
      assert.same("another generic check error", errs["@entity"][2])
      assert.string(errs["fail1"])
      assert.same("my own field error", errs["fail2"])
    end)

    it("can make a string from an error", function()
      local Test = Schema.new({
        fields = {
          { foo = { type = "typo" }, },
        }
      })
      local ret, errs = Test:validate({ foo = "foo" })
      assert.falsy(ret)
      assert.string(errs["foo"])

      local errmsg = Test:errors_to_string(errs)
      assert.string(errmsg)

      -- Produced string mentions the relevant error
      assert.match("foo", errmsg)
    end)

    it("produces no string when given no errors", function()
      local Test = Schema.new({
        fields = {}
      })
      local errmsg = Test:errors_to_string({})
      assert.falsy(errmsg)
      errmsg = Test:errors_to_string(nil)
      assert.falsy(errmsg)
      errmsg = Test:errors_to_string("not a table")
      assert.falsy(errmsg)
    end)

    describe("subschemas", function()
      it("validates loading a subschema", function()
        local Test = Schema.new({
          name = "test",
          subschema_key = "name",
          fields = {
            { name = { type = "string", required = true, } },
            { config = { type = "record", abstract = true, } },
          }
        })
        Test:new_subschema("my_subschema", {
          fields = {
            { config = {
                type = "record",
                fields = {
                  { foo = { type = "string" } },
                  { bar = { type = "integer" } },
                }
            } }
          }
        })
        assert.truthy(Test:validate({
          name = "my_subschema",
          config = {
            foo = "hello",
            bar = 123,
          }
        }))
      end)

      it("fails if subschema doesn't exist", function()
        local Test = Schema.new({
          name = "test",
          subschema_key = "name",
          fields = {
            { name = { type = "string", required = true, } },
          }
        })
        local ok, errors = Test:validate({
          name = "my_invalid_subschema",
        })
        assert.falsy(ok)
        assert.same({
          ["name"] = "unknown type: my_invalid_subschema",
        }, errors)
      end)

      it("ignores missing non-required abstract fields", function()
        local Test = Schema.new({
          name = "test",
          subschema_key = "name",
          fields = {
            { name = { type = "string", required = true, } },
            { config = { type = "record", abstract = true, } },
            { bla = { type = "integer", abstract = true, } },
          }
        })
        Test:new_subschema("my_subschema", {
          fields = {
            { config = {
                type = "record",
                fields = {
                  { foo = { type = "string" } },
                  { bar = { type = "integer" } },
                }
            } }
          }
        })
        assert.truthy(Test:validate({
          name = "my_subschema",
          config = {
            foo = "hello",
            bar = 123,
          }
        }))
      end)

      it("cannot introduce new top-level fields", function()
        local Test = Schema.new({
          name = "test",
          subschema_key = "name",
          fields = {
            { name = { type = "string", required = true, } },
            { config = {
                type = "record",
                fields = {
                  { foo = { type = "integer" } },
                }
            } },
          }
        })
        Test:new_subschema("my_subschema", {
          fields = {
            { config = {
                type = "record",
                fields = {
                  { foo = { type = "integer" } },
                  { bar = { type = "integer" } },
                }
            } },
            { new_field = { type = "string", required = true, } },
          }
        })

        local ok, errors = Test:validate({
          name = "my_subschema",
          config = {
            foo = 123,
          },
          new_field = "blah",
        })
        assert.falsy(ok)
        assert.same({
          new_field = "unknown field",
        }, errors)
      end)

      it("fails when trying to use an abstract field (incomplete subschema)", function()
        local Test = Schema.new({
          name = "test",
          subschema_key = "name",
          fields = {
            { name = { type = "string", required = true, } },
            { config = { type = "record", abstract = true, } },
            { bla = { type = "integer", abstract = true, } },
          }
        })
        Test:new_subschema("my_subschema", {
          fields = {
            { config = {
                type = "record",
                fields = {
                  { foo = { type = "string" } },
                  { bar = { type = "integer" } },
                }
            } }
          }
        })
        local ok, errors = Test:validate({
          name = "my_subschema",
          config = {
            foo = "hello",
            bar = 123,
          },
          bla = 456,
        })
        assert.falsy(ok)
        assert.same({
          bla = "error in schema definition: abstract field was not specialized",
        }, errors)
      end)

      it("validates using both schema and subschema", function()
        local Test = Schema.new({
          name = "test",
          subschema_key = "name",
          fields = {
            { name = { type = "string", required = true, } },
            { bla = { type = "integer", } },
            { config = { type = "record", abstract = true, } },
          }
        })
        Test:new_subschema("my_subschema", {
          fields = {
            { config = {
                type = "record",
                fields = {
                  { foo = { type = "string" } },
                  { bar = { type = "integer" } },
                }
            } }
          }
        })
        local ok, errors = Test:validate({
          name = "my_subschema",
          bla = 4.5,
          config = {
            foo = 456,
            bar = 123,
          }
        })
        assert.falsy(ok)
        assert.same({
          bla = "expected an integer",
          config = {
            foo = "expected a string",
          }
        }, errors)
      end)

      it("can specialize a field of the parent schema", function()
        local Test = Schema.new({
          name = "test",
          subschema_key = "name",
          fields = {
            { name = { type = "string", required = true, } },
            { consumer = { type = "string", } },
          }
        })
        Test:new_subschema("length_5", {
          fields = {
            { consumer = {
                type = "string",
                len_eq = 5,
            } }
          }
        })
        Test:new_subschema("no_restrictions", {
          fields = {}
        })

        local ok, errors = Test:validate({
          name = "length_5",
          consumer = "aaa",
        })
        assert.falsy(ok)
        assert.same({
          consumer = "length must be 5",
        }, errors)

        ok = Test:validate({
          name = "length_5",
          consumer = "aaaaa",
        })
        assert.truthy(ok)

        ok = Test:validate({
          name = "no_restrictions",
          consumer = "aaa",
        })
        assert.truthy(ok)

      end)

      it("cannot change type when specializing a field", function()
        local Test = Schema.new({
          name = "test",
          subschema_key = "name",
          fields = {
            { name = { type = "string", required = true, } },
            { consumer = { type = "string", } },
          }
        })
        Test:new_subschema("length_5", {
          fields = {
            { consumer = {
                type = "integer",
            } }
          }
        })
        Test:new_subschema("no_restrictions", {
          fields = {}
        })

        local ok, errors = Test:validate({
          name = "length_5",
          consumer = "aaaaa",
        })
        assert.falsy(ok)
        assert.same({
          consumer = "error in schema definition: cannot change type in a specialized field",
        }, errors)

        ok = Test:validate({
          name = "no_restrictions",
          consumer = "aaa",
        })
        assert.truthy(ok)

      end)

      it("a specialized field can force a value using 'eq'", function()
        assert(Schema.new({
          name = "mock_consumers",
          primary_key = { "id" },
          fields = {
            { id = { type = "string" }, },
          }
        }))

        local Test = assert(Schema.new({
          name = "test",
          subschema_key = "name",
          fields = {
            { name = { type = "string", required = true, } },
            { consumer = { type = "foreign", reference = "mock_consumers" } },
          }
        }))
        Test:new_subschema("no_consumer", {
          fields = {
            { consumer = { type = "foreign", reference = "mock_consumers", eq = ngx.null } }
          }
        })
        Test:new_subschema("no_restrictions", {
          fields = {}
        })

        local ok, errors = Test:validate({
          name = "no_consumer",
          consumer = { id = "hello" },
        })
        assert.falsy(ok)
        assert.same({
          consumer = "value must be null",
        }, errors)

        ok = Test:validate({
          name = "no_consumer",
          consumer = ngx.null,
        })
        assert.truthy(ok)

        ok = Test:validate({
          name = "no_restrictions",
          consumer = { id = "hello" },
        })
        assert.truthy(ok)

      end)

    end)

  end)

  describe("validate_primary_key", function()

    it("validates primary keys", function()
      local Test = Schema.new({
        fields = {
          { a = { type = "string"  }, },
          { b = { type = "number" }, },
          { c = { type = "number", default = 110 }, },
        }
      })
      Test.primary_key = { "a", "c" }
      assert.truthy(Test:validate_primary_key({
        a = "hello",
        c = 195
      }))
    end)

    it("fails on missing required primary keys", function()
      local Test = Schema.new({
        fields = {
          { a = { type = "string"  }, },
          { b = { type = "number" }, },
          { c = { type = "number", required = true }, },
        }
      })
      Test.primary_key = { "a", "c" }
      local ok, errs = Test:validate_primary_key({
        a = "hello",
      })
      assert.falsy(ok)
      assert.truthy(errs["c"])
    end)

    it("fails on missing foreign primary keys", function()
      assert(Schema.new({
        name = "schema-test",
        primary_key = { "id" },
        fields = {
          { id = { type = "string" }, },
        }
      }))
      local Test = assert(Schema.new({
        name = "Test",
        fields = {
          { f = { type = "foreign", reference = "schema-test" } },
          { b = { type = "number" }, },
          { c = { type = "number" }, },
        }
      }))
      Test.primary_key = { "f" }
      local ok, errs = Test:validate_primary_key({})
      assert.falsy(ok)
      assert.match("missing primary key", errs["f"])
    end)

    it("fails on bad foreign primary keys", function()
      assert(Schema.new({
        name = "schema-test",
        primary_key = { "id" },
        fields = {
          { id = { type = "string", required = true }, },
        }
      }))
      local Test = assert(Schema.new({
        name = "Test",
        fields = {
          { f = { type = "foreign", reference = "schema-test" } },
          { b = { type = "number" }, },
          { c = { type = "number" }, },
        }
      }))
      Test.primary_key = { "f" }
      local ok, errs = Test:validate_primary_key({
        f = { id = ngx.null },
      })
      assert.falsy(ok)
      assert.match("required field missing", errs["f"].id)
    end)

    it("accepts a null in foreign if a null fails on bad foreign primary keys", function()
      package.loaded["kong.db.schema.entities.schema-test"] = {
        name = "schema-test",
        primary_key = { "id" },
        fields = {
          { id = { type = "string", required = true }, },
        }
      }
      local Test = assert(Schema.new({
        name = "Test",
        fields = {
          { f = { type = "foreign", reference = "schema-test" } },
          { b = { type = "number" }, },
          { c = { type = "number" }, },
        }
      }))
      Test.primary_key = { "f" }
      local ok, errs = Test:validate_primary_key({
        f = { id = ngx.null },
      })
      assert.falsy(ok)
      assert.match("required field missing", errs["f"].id)
    end)

    it("fails given non-primary keys", function()
      local Test = Schema.new({
        fields = {
          { a = { type = "string"  }, },
          { b = { type = "number" }, },
          { c = { type = "number", required = true }, },
        }
      })
      Test.primary_key = { "a", "c" }
      local ok, errs = Test:validate_primary_key({
        a = "hello",
        b = 123,
        c = 9,
      })
      assert.falsy(ok)
      assert.truthy(errs["b"])
    end)

    it("fails given invalid keys", function()
      local Test = Schema.new({
        fields = {
          { a = { type = "string"  }, },
          { b = { type = "number" }, },
          { c = { type = "number", required = true }, },
        }
      })
      Test.primary_key = { "a", "c" }
      local ok, errs = Test:validate_primary_key({
        a = "hello",
        x = 123,
      })
      assert.falsy(ok)
      assert.truthy(errs["x"])
    end)

    it("fails on missing non-required primary key", function()
      local Test = Schema.new({
        fields = {
          a = { type = "string"  },
          b = { type = "number" },
          c = { type = "number" },
        }
      })
      Test.primary_key = { "a", "c" }
      assert.falsy(Test:validate_primary_key({
        a = "hello",
      }))
    end)

  end)

  describe("validate_insert", function()

    it("demands required fields", function()
      local Test = Schema.new({
        fields = {
          { f = { type = "number", required = true } }
        }
      })
      assert.truthy(Test:validate_insert({ f = 123 }))
      assert.falsy(Test:validate_insert({}))
    end)

  end)

  describe("validate_update", function()

    it("does not demand required fields", function()
      local Test = Schema.new({
        fields = {
          { f = { type = "number", required = true } }
        }
      })
      assert.truthy(Test:validate_update({ f = 123 }))
      assert.truthy(Test:validate_update({}))
    end)

    it("demands interdependent fields", function()
      local Test = Schema.new({
        fields = {
          { a = { type = "number" } },
          { b = { type = "number" } },
          { c = { type = "number" } },
          { d = { type = "number" } },
        },
        entity_checks = {
          { only_one_of = { "a", "b" } },
        }
      })
      assert.falsy(Test:validate_update({ a = 12 }))
      assert.truthy(Test:validate_update({ a = 12, b = ngx.null }))
    end)

    it("test conditional checks", function()
      local Test = Schema.new({
        fields = {
          { policy = { type = "string", one_of = { "redis", "bla" } } },
          { redis_host = { type = "string" } },
          { redis_port = { type = "number" } },
        },
        entity_checks = {
          { conditional = { if_field = "policy",
                            if_match = { match = "^redis$" },
                            then_field = "redis_host",
                            then_match = { required = true } } },
          { conditional = { if_field = "policy",
                            if_match = { match = "^redis$" },
                            then_field = "redis_port",
                            then_match = { required = true } } },
        }
      })
      local ok, err = Test:validate_update({ policy = "redis" })
      assert.falsy(ok)
      assert.truthy(err)
      assert.falsy(Test:validate_update({
        policy = "redis",
        redis_host = ngx.null,
        redis_port = ngx.null,
      }))
      assert.truthy(Test:validate_update({
        policy = "redis",
        redis_host = "example.com",
        redis_port = 80
      }))
      assert.truthy(Test:validate_update({
        policy = "bla",
      }))
      assert.falsy(Test:validate_update({
        policy = "redis",
      }))
    end)

    it("test conditional checks on set elements", function()
      local Test = Schema.new({
        fields = {
          { redis_host = { type = "string" } },
          { a_set = { type = "set", elements = { type = "string", one_of = { "foo", "bar" } } } },
        },
        entity_checks = {
          { conditional = { if_field = "a_set",
                            if_match = { elements = { type = "string", one_of = { "foo" } } },
                            then_field = "redis_host",
                            then_match = { eq = "host_foo" } } },
        }
      })
      local ok, err = Test:validate_update({
        a_set = { "foo" },
        redis_host = "host_foo",
      })
      assert.truthy(ok)
      assert.is_nil(err)

      ok, err = Test:validate_update({
        a_set = { "foo" },
        redis_host = "host_bar",
      })
      assert.falsy(ok)
      assert.same("value must be host_foo", err.redis_host)

      ok, err = Test:validate_update({
        a_set = { "bar" },
        redis_host = "any_other_host",
      })
      assert.truthy(ok)
      assert.is_nil(err)
    end)

    it("test custom entity checks", function()
      local Test = Schema.new({
        fields = {
          { aaa = { type = "string" } },
          { bbb = { type = "string" } },
          { ccc = { type = "number" } },
        },
        entity_checks = {
          { custom_entity_check = {
            field_sources = { "bbb", "ccc" },
            fn = function(entity)
              assert(entity.aaa == nil)
              if entity.bbb == "foo" and entity.ccc == 42 then
                return true
              end
              return nil, "oh no"
            end,
          } }
        }
      })
      local ok, err = Test:validate_update({
        aaa = "bar",
        bbb = "foo",
        ccc = 42
      })
      assert.truthy(ok)
      assert.falsy(err)

      ok, err = Test:validate_update({
        aaa = ngx.null,
        bbb = "foo",
        ccc = 42
      })
      assert.truthy(ok)
      assert.falsy(err)

      ok, err = Test:validate({
        aaa = ngx.null,
        bbb = "foo",
      })
      assert.falsy(ok)
      assert.match("field required for entity check", err["ccc"])

      ok, err = Test:validate_update({
        aaa = ngx.null,
        bbb = "foo",
      })
      assert.falsy(ok)
      assert.match("field required for entity check when updating", err["ccc"])

      ok, err = Test:validate_update({
        aaa = ngx.null,
      })
      assert.truthy(ok)
      assert.falsy(err)

      ok, err = Test:validate_update({
        bbb = "foo",
        ccc = 43
      })
      assert.falsy(ok)
      assert.match("oh no", err["@entity"][1])

      ok, err = Test:validate_update({
        bbb = "foooo",
        ccc = 42
      })
      assert.falsy(ok)
      assert.match("oh no", err["@entity"][1])
    end)

    it("does not run an entity check if fields have errors", function()
      local Test = Schema.new({
        fields = {
          { aaa = { type = "string" } },
          { bbb = { type = "string", len_min = 8 } },
          { ccc = { type = "number", between = { 0, 10 } } },
        },
        entity_checks = {
          { custom_entity_check = {
            field_sources = { "bbb", "ccc" },
            fn = function(entity)
              assert(entity.aaa == nil)
              if entity.bbb == "12345678" and entity.ccc == 2 then
                return true
              end
              return nil, "oh no"
            end,
          } }
        }
      })
      local ok, err = Test:validate_update({
        aaa = "bar",
        bbb = "foo",
        ccc = 42
      })
      assert.falsy(ok)
      assert.match("length must be at least 8", err["bbb"])
      assert.match("value should be between 0 and 10", err["ccc"])
      assert.falsy(err["@entity"])

      ok, err = Test:validate({
        aaa = ngx.null,
        bbb = "foo",
        ccc = 42
      })
      assert.falsy(ok)
      assert.match("length must be at least 8", err["bbb"])
      assert.match("value should be between 0 and 10", err["ccc"])
      assert.falsy(err["@entity"])

      ok, err = Test:validate({
        bbb = "AAAAAAAA",
        ccc = 9,
      })
      assert.falsy(ok)
      assert.match("oh no", err["@entity"][1])

      ok, err = Test:validate({
        bbb = "12345678",
        ccc = 2,
      })
      assert.truthy(ok)
      assert.falsy(err)
    end)

    it("supports entity checks on nested fields", function()
      local Test = Schema.new({
        fields = {
          { config = {
              type = "record",
              fields = {
                { policy = { type = "string", one_of = { "redis", "bla" } } },
                { redis_host = { type = "string" } },
                { redis_port = { type = "number" } },
              }
          } }
        },
        entity_checks = {
          { conditional = { if_field = "config.policy",
                            if_match = { eq = "redis" },
                            then_field = "config.redis_host",
                            then_match = { required = true } } },
          { conditional = { if_field = "config.policy",
                            if_match = { eq = "redis" },
                            then_field = "config.redis_port",
                            then_match = { required = true } } },
        }
      })
      local ok, err = Test:validate_update({ config = { policy = "redis" } })
      assert.falsy(ok)
      assert.truthy(err)
      assert.falsy(Test:validate_update({
        config = {
          policy = "redis",
          redis_host = ngx.null,
          redis_port = ngx.null,
        }
      }))
      assert.truthy(Test:validate_update({
        config = {
          policy = "redis",
          redis_host = "example.com",
          redis_port = 80
        }
      }))
      assert.falsy(Test:validate_update({
        config = {
          policy = "redis",
        }
      }))
      assert.truthy(Test:validate_update({
        config = {
          policy = "bla",
        }
      }))
    end)

    it("does not demand interdependent fields that aren't being updated", function()
      local Test = Schema.new({
        fields = {
          { a = { type = "number" } },
          { b = { type = "number" } },
          { c = { type = "number" } },
          { d = { type = "number" } },
        },
        entity_checks = {
          { only_one_of = { "a", "b" } },
        }
      })
      assert.truthy(Test:validate_update({ c = 15 }))
    end)

  end)

  describe("process_auto_fields", function()

    it("produces ngx.null for non-required fields", function()
      local Test = Schema.new({
        fields = {
          { a = { type = "array", elements = { type = "string" } }, },
          { b = { type = "set", elements = { type = "string" } }, },
          { c = { type = "number" }, },
          { d = { type = "integer" }, },
          { e = { type = "boolean" }, },
          { f = { type = "string" }, },
          { g = { type = "record", fields = {} }, },
          { h = { type = "map", keys = {}, values = {} }, },
          { i = { type = "function" }, },
        }
      })
      check_all_types_covered(Test.fields)
      local data, err = Test:process_auto_fields({})
      assert.is_nil(err)
      assert.same(ngx.null, data.a)
      assert.same(ngx.null, data.b)
      assert.same(ngx.null, data.c)
      assert.same(ngx.null, data.d)
      assert.same(ngx.null, data.e)
      assert.same(ngx.null, data.f)
      assert.same(ngx.null, data.g)
      assert.same(ngx.null, data.h)
      assert.same(ngx.null, data.i)
    end)

    it("does not produce non-required fields on 'update'", function()
      local Test = Schema.new({
        fields = {
          { a = { type = "array", elements = { type = "string" } }, },
          { b = { type = "set", elements = { type = "string" } }, },
          { c = { type = "number" }, },
          { d = { type = "integer" }, },
          { e = { type = "boolean" }, },
          { f = { type = "string" }, },
          { g = { type = "record", fields = {} }, },
          { h = { type = "map", keys = {}, values = {} }, },
          { i = { type = "function" }, },
        }
      })
      check_all_types_covered(Test.fields)
      local data, err = Test:process_auto_fields({}, "update")
      assert.is_nil(err)
      assert.is_nil(data.a)
      assert.is_nil(data.b)
      assert.is_nil(data.c)
      assert.is_nil(data.d)
      assert.is_nil(data.e)
      assert.is_nil(data.f)
      assert.is_nil(data.g)
      assert.is_nil(data.h)
      assert.is_nil(data.i)
    end)

    it("honors given default values", function()
      local f = function() end

      local Test = Schema.new({
        fields = {
          { a = { type = "array",
                  elements = { type = "string" },
                  default = { "foo", "bar" } }, },
          { b = { type = "set",
                  elements = { type = "number" },
                  default = { 2112, 5150 } }, },
          { c = { type = "number", default = 1984 }, },
          { d = { type = "integer", default = 42 }, },
          { e = { type = "boolean", default = true }, },
          { f = { type = "string", default = "foo" }, },
          { g = { type = "map",
                  keys = { type = "string" },
                  values = { type = "number" },
                  default = { foo = 1, bar = 2 } }, },
          { h = { type = "record",
                        fields = {
                    { f = { type = "number" }, },
                  },
                  default = { f = 123 } }, },
          { i = { type = "function", default = f } },
          { nested_record = {
              type = "record",
              default = {
                r = {
                  a = "nr",
                  b = 123,
                }
              },
              fields = {
                { r = {
                    type = "record",
                    fields = {
                      { a = { type = "string" } },
                      { b = { type = "number" } }
                    }
                } }
              }
          } }
        }
      })
      check_all_types_covered(Test.fields)
      local data = Test:process_auto_fields({})
      assert.same({ "foo", "bar" },     data.a)
      assert.same({ 2112, 5150 },       data.b)
      assert.same(1984,                 data.c)
      assert.same(42,                   data.d)
      assert.is_true(data.e)
      assert.same("foo",                data.f)
      assert.same({ foo = 1, bar = 2 }, data.g)
      assert.same({ f = 123 },          data.h)
      assert.same(f,                    data.i)
      assert.same({ r = { a = "nr", b = 123, }}, data.nested_record)
    end)

    it("nested defaults in non-nullable records produce a default record", function()
      local Test = Schema.new({
        fields = {
          { nested_record = {
              type = "record",
              nullable = false,
              fields = {
                { r = {
                    type = "record",
                    nullable = false,
                    fields = {
                      { a = { type = "string", default = "nr", } },
                      { b = { type = "number", default = 123, } }
                    }
                } }
              }
          } }
        }
      })
      local data = Test:process_auto_fields({})
      assert.same({ r = { a = "nr", b = 123, }}, data.nested_record)
    end)

    it("honors 'false' as a default", function()
      local Test = Schema.new({
        fields = {
          { b = { type = "boolean", default = false }, },
        }
      })
      local t1 = Test:process_auto_fields({})
      assert.is_false(t1.b)
      local t2 = Test:process_auto_fields({ b = false })
      assert.is_false(t2.b)
      local t3 = Test:process_auto_fields({ b = true })
      assert.is_true(t3.b)
    end)

    it("honors 'true' as a default", function()
      local Test = Schema.new({
        fields = {
          { b = { type = "boolean", default = true }, },
        }
      })
      local t1 = Test:process_auto_fields({})
      assert.is_true(t1.b)
      local t2 = Test:process_auto_fields({ b = false })
      assert.is_false(t2.b)
      local t3 = Test:process_auto_fields({ b = true })
      assert.is_true(t3.b)
    end)

    it("does not demand required fields", function()
      local Test = Schema.new({
        fields = {
          { f = { type = "number", required = true } }
        }
      })
      assert.truthy(Test:process_auto_fields({ f = 123 }))
      assert.truthy(Test:process_auto_fields({}))
    end)

    it("removes duplicates preserving order", function()
      local Test = Schema.new({
        fields = {
          { f = { type = "set", elements = { type = "string" } } }
        }
      })
      local tests = {
        { {}, {} },
        { {"foo"}, {"foo"} },
        { {"foo", "bar"}, {"foo", "bar"} },
        { {"bar", "foo"}, {"bar", "foo"} },
        { {"foo", "foo", "bar"}, {"foo", "bar"} },
        { {"foo", "bar", "foo"}, {"foo", "bar"} },
        { {"foo", "foo", "foo"}, {"foo"} },
        { {"bar", "foo", "foo"}, {"bar", "foo"} },
      }
      for _, test in ipairs(tests) do
        assert.same({ f = test[2] }, Test:process_auto_fields({ f = test[1] }))
      end
    end)

    -- TODO is this behavior correct?
    it("non-required fields do not generate defaults", function()
      local Test = Schema.new({
        fields = {
          { f = { type = "number" }, },
        }
      })
      local data = Test:process_auto_fields({})
      assert.same(ngx.null, data.f)
    end)

    it("auto-produces an UUID with 'uuid' and 'auto'", function()
      local Test = Schema.new({
        fields = {
          { f = { type = "string", uuid = true, auto = true } }
        }
      })
      local tbl = {}
      tbl = Test:process_auto_fields(tbl, "insert")
      assert.match(uuid_pattern, tbl.f)
    end)

    it("auto-produces a random with 'string' and 'auto'", function()
      local Test = Schema.new({
        fields = {
          { f = { type = "string", auto = true } }
        }
      })
      local tbl = {}
      tbl = Test:process_auto_fields(tbl, "insert")
      assert.is_string(tbl.f)
      assert.equals(32, #tbl.f)
    end)

    it("auto-produces a timestamp with 'created_at' and 'auto'", function()
      local Test = Schema.new({
        fields = {
          { created_at = { type = "number", timestamp = true, auto = true } }
        }
      })
      local tbl = {}
      -- Does not insert `created_at` on "update"
      tbl = Test:process_auto_fields(tbl, "update")
      assert.falsy(tbl.created_at)
      -- It does insert it on "insert"
      tbl = Test:process_auto_fields(tbl, "insert")
      assert.number(tbl.created_at)
    end)

    it("auto-updates a timestamp with 'updated_at' and 'auto'", function()
      local Test = Schema.new({
        fields = {
          { updated_at = { type = "number", timestamp = true, auto = true } }
        }
      })
      local tbl = {}
      tbl = Test:process_auto_fields(tbl, "update")
      assert.number(tbl.updated_at)
      -- force updated_at downwards...
      local ts = tbl.updated_at - 10
      tbl.updated_at = ts
      -- ...and updates it again
      tbl = Test:process_auto_fields(tbl, "update")
      assert.number(tbl.updated_at)
      -- Note: this assumes the clock only moves forwards during the execution
      -- of the test. As we store UTC timestamps, we're immune to DST
      -- downward adjustments, and ntp leap second adjustments only move
      -- forward.
      assert.truthy(tbl.updated_at > ts)
    end)

    it("does not auto-update a timestamp with 'created_at' or 'updated_at' and 'auto' upon retrival", function()
      local Test = Schema.new({
        fields = {
          { created_at = { type = "number", timestamp = true, auto = true } },
          { updated_at = { type = "number", timestamp = true, auto = true } },
        }
      })
      local tbl = {}
      tbl = Test:process_auto_fields(tbl, "insert")
      assert.number(tbl.created_at)
      assert.number(tbl.updated_at)
      -- force updated_at downwards...
      local created_ts = tbl.created_at - 10
      local updated_ts = tbl.updated_at - 10
      tbl.created_at = created_ts
      tbl.updated_at = updated_ts
      -- ...and doesn't updates it again
      tbl = Test:process_auto_fields(tbl, "select")
      assert.number(tbl.created_at)
      assert.same(updated_ts, tbl.created_at)
      assert.number(tbl.updated_at)
      assert.same(updated_ts, tbl.updated_at)
    end)

    it("adds cjson.empty_array_mt on empty array and set fields", function()
      local Test = Schema.new({
        fields = {
          { arr = { type = "array", elements = { type = "string" } } },
          { set = { type = "set",   elements = { type = "string" } } },
        },
      })

      local tbl = Test:process_auto_fields({
        arr = {},
        set = {}
      }, "insert")

      assert.same(cjson.empty_array_mt, getmetatable(tbl.arr))
      assert.same(cjson.empty_array_mt, getmetatable(tbl.set))
    end)

    it("adds cjson.empty_array_mt on empty array and set fields", function()
      local Test = Schema.new({
        fields = {
          { arr = { type = "array", elements = { type = "string" } } },
          { set = { type = "set",   elements = { type = "string" } } },
        },
      })

      for _, operation in pairs{ "insert", "update", "select", "delete" } do
        local tbl = Test:process_auto_fields({
          arr = {},
          set = {}
        }, operation)

        assert.same(cjson.empty_array_mt, getmetatable(tbl.arr))
        assert.same(cjson.empty_array_mt, getmetatable(tbl.set))
      end
    end)

    it("adds a helper metatable to sets", function()
      local Test = Schema.new({
        fields = {
          { set = { type = "set", elements = { type = "string" } } },
        },
      })

      for _, operation in pairs{ "insert", "update", "select", "delete" } do
        local tbl = Test:process_auto_fields({
          set = { "http", "https" },
        }, operation)


        assert.equal("table", type(getmetatable(tbl.set)))

        assert.truthy(tbl.set.http)
        assert.truthy(tbl.set.https)
        assert.falsy(tbl.set.smtp)
      end
    end)

    it("does not add a helper metatable to arrays or maps", function()
      local Test = Schema.new({
        fields = {
          { arr = { type = "array", elements = { type = "string" } } },
          { map = { type = "map", keys = { type = "string" }, values = { type = "boolean" } } },
        },
      })

      for _, operation in pairs{ "insert", "update", "select", "delete" } do
        local tbl = Test:process_auto_fields({
          arr = { "http", "https" },
          map = { http = true },
        }, operation)

        assert.is_nil(getmetatable(tbl.arr))
        assert.is_nil(getmetatable(tbl.map))
        assert.is_equal("http", tbl.arr[1])
        assert.is_nil(tbl.arr.http)
        assert.is_true(tbl.map.http)
        assert.is_nil(tbl.map.https)
      end
    end)

    describe("in subschemas", function()
      it("a specialized field can set a default", function()
        local Test = Schema.new({
          name = "test",
          subschema_key = "name",
          fields = {
            { name = { type = "string", required = true, } },
            { config = { type = "record", abstract = true } },
          }
        })
        Test:new_subschema("my_subschema", {
          fields = {
            { config = {
                type = "record",
                fields = {
                  { foo = { type = "string", default = "bar" } },
                },
                default = { foo = "bla" }
             } }
          }
        })

        local input = {
          name = "my_subschema",
          config = { foo = "hello" },
        }
        local ok = Test:validate(input)
        assert.truthy(ok)
        local output = Test:process_auto_fields(input)
        assert.same(input, output)

        input = {
          name = "my_subschema",
          config = nil,
        }
        ok = Test:validate(input)
        assert.truthy(ok)
        output = Test:process_auto_fields(input)
        assert.same({
          name = "my_subschema",
          config = {
            foo = "bla",
          }
        }, output)

      end)
    end)

  end)
end)
