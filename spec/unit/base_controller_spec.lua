local base_controller = require "kong.api.routes.base_controller"
local spec_helper = require "spec.spec_helpers" -- ngx stub

local stub = {
  req = { headers = {} },
  add_params = function() end,
  params = { foo = "bar", number = 10, ["value.nested"] = 1, ["value.nested_2"] = 2 }
}

describe("Base Controller", function()
  describe("#parse_params()", function()

    it("should normalize nested properties for parsed form-encoded parameters", function()
      -- Here Lapis already parsed the form-encoded parameters but we are normalizing
      -- the nested ones (with "." keys)
      local f = base_controller.parse_params(function(stub)
        assert.are.same({
          foo = "bar",
          number = 10,
          value = {
            nested = 1,
            nested_2 = 2
          }
        }, stub.params)
      end)
      f(stub)
    end)

    it("should parse a JSON body", function()
      -- Here we are simply decoding a JSON body (which is a string)
      ngx.req.get_body_data = function() return '{"foo":"bar","number":10,"value":{"nested":1,"nested_2":2}}' end
      stub.req.headers["Content-Type"] = "application/json; charset=utf-8"

      local f = base_controller.parse_params(function(stub)
        assert.are.same({
          foo = "bar",
          number = 10,
          value = {
            nested = 1,
            nested_2 = 2
          }
        }, stub.params)
      end)
      f(stub)
    end)

    it("should normalize sub-nested properties for parsed form-encoded parameters", function()
      stub.params = { foo = "bar", number = 10, ["value.nested_1"] = 1, ["value.nested_2"] = 2,
        ["value.nested.sub-nested"] = "hi"
      }
      local f = base_controller.parse_params(function(stub)
        assert.are.same({
          foo = 'bar',
          number = 10,
          value = {
            nested = {
              ["sub-nested"] = "hi"
            },
            nested_1 = 1,
            nested_2 = 2
        }}, stub.params)
      end)
      f(stub)
    end)

    it("should normalize nested properties when they are plain arrays", function()
      stub.params = { foo = "bar", number = 10, ["value.nested"] = {["1"]="hello", ["2"]="world"}}
      local f = base_controller.parse_params(function(stub)
        assert.are.same({
          foo = 'bar',
          number = 10,
          value = {
            nested = {"hello", "world"},
        }}, stub.params)
      end)
      f(stub)
    end)

  end)
end)
