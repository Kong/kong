-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local api_helpers = require "kong.api.api_helpers"
local norm = api_helpers.normalize_nested_params

describe("api_helpers", function()
  describe("normalize_nested_params()", function()
    it("handles nested & mixed data structures", function()
      assert.same({ ["hello world"] = "foo, bar", falsy = false },
                  norm({ ["hello world"] = "foo, bar", falsy = false }))

      assert.same({ array = { "alice", "bob", "casius" } },
                  norm({ ["array[1]"] = "alice",
                         ["array[2]"] = "bob",
                         ["array[3]"] = "casius" }))

      assert.same({ hash = { answer = 42 } },
                  norm({ ["hash.answer"] = 42 }))

      assert.same({ hash_array = { arr = { "one", "two" } } },
                  norm({ ["hash_array.arr[1]"] = "one",
                         ["hash_array.arr[2]"] = "two" }))

      assert.same({ array_hash = { { name = "peter" } } },
                  norm({ ["array_hash[1].name"] = "peter" }))

      assert.same({ array_array = { { "x", "y" } } },
                  norm({ ["array_array[1][1]"] = "x",
                         ["array_array[1][2]"] = "y" }))

      assert.same({ hybrid = { 1, 2, n = 3 } },
                  norm({ ["hybrid[1]"] = 1,
                         ["hybrid[2]"] = 2,
                         ["hybrid.n"] = 3 }))
    end)
    it("handles nested & mixed data structures with omitted array indexes", function()
      assert.same({ array = { "alice", "bob", "casius" } },
                  norm({ ["array[]"] = {"alice", "bob", "casius"} }))

      assert.same({ hash_array = { arr = { "one", "two" } } },
                  norm({ ["hash_array.arr[]"] = { "one", "two" } }))

      assert.same({ array_hash = { { name = "peter" } } },
                  norm({ ["array_hash[].name"] = "peter" }))

      assert.same({ array_array = { { "x", "y" } } },
                  norm({ ["array_array[][]"] = { "x", "y" } }))

      assert.same({ hybrid = { 1, 2, n = 3 } },
                  norm({ ["hybrid[]"] = { 1, 2 },
                         ["hybrid.n"] = 3 }))
    end)
    it("complete use case", function()
      assert.same({
        service_id = 123,
        name = "request-transformer",
        config = {
          add = {
            form = "new-form-param:some_value, another-form-param:some_value",
            headers = "x-new-header:some_value, x-another-header:some_value",
            querystring = "new-param:some_value, another-param:some_value"
          },
          remove = {
            form = "formparam-toremove",
            headers = "x-toremove, x-another-one",
            querystring = "param-toremove, param-another-one"
          }
        }
      }, norm {
        service_id = 123,
        name = "request-transformer",
        ["config.add.headers"] = "x-new-header:some_value, x-another-header:some_value",
        ["config.add.querystring"] = "new-param:some_value, another-param:some_value",
        ["config.add.form"] = "new-form-param:some_value, another-form-param:some_value",
        ["config.remove.headers"] = "x-toremove, x-another-one",
        ["config.remove.querystring"] = "param-toremove, param-another-one",
        ["config.remove.form"] = "formparam-toremove"
      })
    end)
  end)
end)
