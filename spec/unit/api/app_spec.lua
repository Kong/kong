local app = require "kong.api.app"

require "kong.tools.ngx_stub"

local stub = {
  req = { headers = {} },
  add_params = function() end,
  params = { foo = "bar", number = 10, ["config.nested"] = 1, ["config.nested_2"] = 2 }
}

describe("App", function()
  describe("#parse_params()", function()

    it("should normalize nested properties for parsed form-encoded parameters", function()
      -- Here Lapis already parsed the form-encoded parameters but we are normalizing
      -- the nested ones (with "." keys)
      local f = app.parse_params(function(stub)
        assert.are.same({
          foo = "bar",
          number = 10,
          config = {
            nested = 1,
            nested_2 = 2
          }
        }, stub.params)
      end)
      f(stub)
    end)

    it("should parse a JSON body", function()
      -- Here we are simply decoding a JSON body (which is a string)
      ngx.req.get_body_data = function() return '{"foo":"bar","number":10,"config":{"nested":1,"nested_2":2}}' end
      stub.req.headers["Content-Type"] = "application/json; charset=utf-8"

      local f = app.parse_params(function(stub)
        assert.are.same({
          foo = "bar",
          number = 10,
          config = {
            nested = 1,
            nested_2 = 2
          }
        }, stub.params)
      end)
      f(stub)
    end)

    it("should normalize sub-nested properties for parsed form-encoded parameters", function()
      stub.params = { foo = "bar", number = 10, ["config.nested_1"] = 1, ["config.nested_2"] = 2,
        ["config.nested.sub-nested"] = "hi"
      }
      local f = app.parse_params(function(stub)
        assert.are.same({
          foo = 'bar',
          number = 10,
          config = {
            nested = {
              ["sub-nested"] = "hi"
            },
            nested_1 = 1,
            nested_2 = 2
          }
        }, stub.params)
      end)
      f(stub)
    end)

    it("should normalize nested properties when they are plain arrays", function()
      stub.params = { foo = "bar", number = 10, ["config.nested"] = {["1"]="hello", ["2"]="world"}}
      local f = app.parse_params(function(stub)
        assert.are.same({
          foo = 'bar',
          number = 10,
          config = {
            nested = {"hello", "world"},
        }}, stub.params)
      end)
      f(stub)
    end)

    it("should normalize very complex values", function()
      stub.params = {
        api_id = 123,
        name = "request-transformer",
        ["config.add.headers"] = "x-new-header:some_value, x-another-header:some_value",
        ["config.add.querystring"] = "new-param:some_value, another-param:some_value",
        ["config.add.form"] = "new-form-param:some_value, another-form-param:some_value",
        ["config.remove.headers"] = "x-toremove, x-another-one",
        ["config.remove.querystring"] = "param-toremove, param-another-one",
        ["config.remove.form"] = "formparam-toremove"
      }

      local f = app.parse_params(function(stub)
        assert.are.same({
          api_id = 123,
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
        }, stub.params)
      end)
      f(stub)
    end)

  end)
end)
