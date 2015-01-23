local Validator = require "apenode.models.validator"
local validate = Validator.validate

-- Ok kids, today we're gonna test a custom validation schema,
-- grab a pair of glasses, this stuff can literally explode.
local collection = "custom_object"
local schema = {
  id = { type = "id" },

  string = { type = "string",
             required = true,
             func = check_account_id },

  url = { type = "string",
          required = true,
          regex = "(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\\-]*[a-zA-Z0-9])\\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\\-]*[A-Za-z0-9])" },

  date = { type = "timestamp",
           default = 123456 },

  default = { type = "string",
              default = function() return "default" end  },

  number = { type = "number",
             func = function(n) if n == 123 then return true else return false, "The value should be 123" end end }
}

describe("Validation", function()

  describe("#validate()", function()

    it("should confirm a valid entity is valid", function()
      local values = { string = "httpbin entity", url = "httpbin.org" }

      local res_values, err = validate(values, schema)
      assert.falsy(err)
      assert.truthy(res_values)
    end)

    it("should set default values if those are variables or functions specified in the validator", function()
      -- Variables
      local values = { string = "httpbin entity", url = "httpbin.org" }

      local res_values, err = validate(values, schema)
      assert.falsy(err)
      assert.truthy(res_values)
      assert.are.same(123456, res_values.date)

      -- Functions
      local values = { string = "httpbin entity", url = "httpbin.org" }

      local res_values, err = validate(values, schema)
      assert.falsy(err)
      assert.truthy(res_values)
      assert.are.same("default", res_values.default)
    end)

    it("should override default values if specified", function()
      -- Variables
      local values = { string = "httpbin entity", url = "httpbin.org", date = 654321 }

      local res_values, err = validate(values, schema)
      assert.falsy(err)
      assert.truthy(res_values)
      assert.are.same(654321, res_values.date)

      -- Functions
      local values = { string = "httpbin entity", url = "httpbin.org", default = "abcdef" }

      local res_values, err = validate(values, schema)
      assert.falsy(err)
      assert.truthy(res_values)
      assert.are.same("abcdef", res_values.default)
    end)

    it("should validate a field against a regex", function()
      local values = { string = "httpbin entity", url = "httpbin_!" }

      local res_values, err = validate(values, schema)
      assert.falsy(res_values)
      assert.are.same("url has an invalid value", err.url)
    end)

    it("should return error when unexpected values are included in the schema", function()
      local values = { string = "httpbin entity", url = "httpbin.org", unexpected = "abcdef" }

      local res_values, err = validate(values, schema)
      assert.falsy(res_values)
      assert.are.same("unexpected is an unknown field", err.unexpected)
    end)

    it("should validate against a custom function", function()
      -- Success
      local values = { string = "httpbin entity", url = "httpbin.org", number = 123 }

      local res_values, err = validate(values, schema)
      assert.falsy(err)
      assert.truthy(res_values)

      -- Error
      local values = { string = "httpbin entity", url = "httpbin.org", number = 456 }

      local res_values, err = validate(values, schema)
      assert.falsy(res_values)
      assert.are.same("The value should be 123", err.number)
    end)

    it("should return errors if trying to pass a property of type id", function()
      local values = { id = 1, string = "httpbin entity", url = "httpbin.org" }

      local res_values, err = validate(values, schema)
      assert.falsy(res_values)
      assert.truthy(err)
      assert.are.same("id is an id and cannot be set", err.id)
    end)

    it("should be able to return multiple errors at once", function()
      local values = { id = 1, string = "httpbin entity", url = "httpbin.org", unexpected = "abcdef" }

      local res_values, err = validate(values, schema)
      assert.falsy(res_values)
      assert.truthy(err)
      assert.are.same("id is an id and cannot be set", err.id)
      assert.are.same("unexpected is an unknown field", err.unexpected)
    end)


    describe("Custom validation function", function()
      local SQLiteFactory = require "apenode.dao.sqlite.factory"
      sqlite_dao = ({ memory = true })

      local s = spy.new(function(value)end)
      local function do_something_with_dao(dao)
        return s
      end

      local schema_2 = {
        something = { type = "number",
                      func = do_something_with_dao(sqlite_dao) },
      }

      it("should be able to call a custom function with custom parameters such as a DAO", function()
        local values = { something = 123 }

        local res_values, err = validate(values, schema_2)
        assert.spy(s).was.called_with(123)
      end)
    end)

  end)
end)
