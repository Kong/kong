-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson = require "cjson"
local json_navigator = require "kong.enterprise_edition.transformations.plugins.json_navigator"

describe("json_navigator", function()
  describe("navigate_and_apply()", function()
    it("sanity", function()
      local json = [[
          {
              "headers": {
                  "Accept": "*/*",
                  "Host": "httpbin.test"
              },
              "students": [
                  {
                      "age": 1,
                      "name": "name1",
                      "location": {
                          "country": "country1",
                          "province": "province1"
                      },
                      "hobbies": ["a", "b", "c"],
                      "empty_array": []
                  },
                  {
                      "age": 2,
                      "name": "name2",
                      "location": {
                          "country": "country2",
                          "province": "province2"
                      },
                      "hobbies": ["c", "d", "e"],
                      "empty_array": []
                  }
              ]
          }
      ]]

      local opts = {
        dots_in_keys = false,
      }

      local navigated = false
      local navigate_cnt = 0
      local navigated_elements = {}
      local navigated_ctxs = {}
      json_navigator.navigate_and_apply(cjson.decode(json), "students.[*].age", function(o, p, ctx)
        navigated = true
        navigate_cnt = navigate_cnt + 1
        table.insert(navigated_elements, { age = o[p] })
        table.insert(navigated_ctxs, require("kong.tools.utils").cycle_aware_deep_copy(ctx))
      end, opts)

      assert.is_true(navigated)
      assert.equal(2, navigate_cnt)
      assert.same({ { age = 1 }, { age = 2 } }, navigated_elements)
      assert.same({
        { index = 1, paths = { "students", 1 } },
        { index = 2, paths = { "students", 2 } }
      }, navigated_ctxs)
    end)
  end)
end)
