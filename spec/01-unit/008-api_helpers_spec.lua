local api_helpers = require "kong.api.api_helpers"
local norm = api_helpers.normalize_nested_params

describe("api_helpers", function()
  describe("normalize_nested_params()", function()
    it("renders table from dot notation", function()
      assert.same({
        foo = "bar",
        number = 10,
        config = {
          nested = 1,
          nested_2 = 2
        }
      }, norm {
        foo = "bar",
        number = 10,
        ["config.nested"] = 1,
        ["config.nested_2"] = 2
      })

      assert.same({
        foo = 'bar',
        number = 10,
        config = {
          nested = {
            ["sub-nested"] = "hi"
          },
          nested_1 = 1,
          nested_2 = 2
        }
      }, norm {
        foo = "bar",
        number = 10,
        ["config.nested_1"] = 1,
        ["config.nested_2"] = 2,
        ["config.nested.sub-nested"] = "hi"
      })
    end)
    it("integer indexes arrays with integer strings", function()
      assert.same({
        foo = 'bar',
        number = 10,
        config = {
          nested = {"hello", "world"},
        }
      }, norm {
        foo = "bar",
        number = 10,
        ["config.nested"] = {["1"] = "hello", ["2"] = "world"}
      })
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
