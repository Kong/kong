local schemas = require "apenode.dao.schemas"
local validate = schemas.validate

describe("Validation", function()

  describe("#validate()", function()
    -- Ok kids, today we're gonna test a custom validation schema,
    -- grab a pair of glasses, this stuff can literally explode.
    local collection = "custom_object"
    local schema = {
      { _ = "string", required = true },
      { _ = "table", type = "table" },
      { _ = "url", regex = "(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\\-]*[a-zA-Z0-9])\\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\\-]*[A-Za-z0-9])" },
      { _ = "date", default = 123456 },
      { _ = "default", default = function() return "default" end  }
    }

    it("should confirm a valid entity is valid", function()
      local values = { string = "httpbin entity", url = "httpbin.org" }

      local valid, err = validate(values, schema)
      assert.falsy(err)
      assert.truthy(valid)
    end)

    it("should invalidate entity if required property is misffing", function()
      local values = { url = "httpbin.org" }

      local valid, err = validate(values, schema)
      assert.falsy(valid)
      assert.truthy(err)
      assert.are.same("string is required", err.string)
    end)

    it("should ensure that a table property is a type table", function()
      -- Failure
      local values = { string = "foo", table = "bar" }

      local valid, err = validate(values, schema)
      assert.falsy(valid)
      assert.truthy(err)
      assert.are.same("table is not a table", err.table)

      -- Success
      local values = { string = "foo", table = { foo = "bar" }}

      local valid, err = validate(values, schema)
      assert.falsy(err)
      assert.truthy(valid)
    end)

    it("should set default values if those are variables or functions specified in the validator", function()
      -- Variables
      local values = { string = "httpbin entity", url = "httpbin.org" }

      local valid, err = validate(values, schema)
      assert.falsy(err)
      assert.truthy(valid)
      assert.are.same(123456, values.date)

      -- Functions
      local values = { string = "httpbin entity", url = "httpbin.org" }

      local valid, err = validate(values, schema)
      assert.falsy(err)
      assert.truthy(valid)
      assert.are.same("default", values.default)
    end)

    it("should override default values if specified", function()
      -- Variables
      local values = { string = "httpbin entity", url = "httpbin.org", date = 654321 }

      local valid, err = validate(values, schema)
      assert.falsy(err)
      assert.truthy(valid)
      assert.are.same(654321, values.date)

      -- Functions
      local values = { string = "httpbin entity", url = "httpbin.org", default = "abcdef" }

      local valid, err = validate(values, schema)
      assert.falsy(err)
      assert.truthy(valid)
      assert.are.same("abcdef", values.default)
    end)

    it("should validate a field against a regex", function()
      local values = { string = "httpbin entity", url = "httpbin_!" }

      local valid, err = validate(values, schema)
      assert.falsy(valid)
      assert.truthy(err)
      assert.are.same("url has an invalid value", err.url)
    end)

    it("should return error when unexpected values are included in the schema", function()
      local values = { string = "httpbin entity", url = "httpbin.org", unexpected = "abcdef" }

      local valid, err = validate(values, schema)
      assert.falsy(valid)
      assert.truthy(err)
      assert.are.same("unexpected is an unknown field", err.unexpected)
    end)

    it("should be able to return multiple errors at once", function()
      local values = { url = "httpbin.org", unexpected = "abcdef" }

      local valid, err = validate(values, schema)
      assert.falsy(valid)
      assert.truthy(err)
      assert.are.same("string is required", err.string)
      assert.are.same("unexpected is an unknown field", err.unexpected)
    end)

  end)
end)
