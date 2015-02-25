local schemas = require "kong.dao.schemas"
local validate = schemas.validate

describe("Validation #schema", function()

  describe("#validate()", function()
    -- Ok kids, today we're gonna test a custom validation schema,
    -- grab a pair of glasses, this stuff can literally explode.
    local collection = "custom_object"
    local schema = {
      string = { required = true, immutable = true },
      table = { type = "table" },
      url = { regex = "(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\\-]*[a-zA-Z0-9])\\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\\-]*[A-Za-z0-9])" },
      date = { default = 123456, immutable = true },
      allowed = { enum = { "hello", "world" }},
      default = { default = function() return "default" end },
      custom = { func = function(v, t)
                          if v then
                            if t.default == "default" then
                              return true
                            else
                              return false, "Nah"
                            end
                          else
                            return true
                          end
                        end },
      sub_schema = {
        schema = {
          sub_field_required = { required = true },
          sub_field_default = { default = "abcd" }
        }
      }
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
    end)

    it("should be able to return multiple errors at once", function()
      local values = { url = "httpbin.org", unexpected = "abcdef" }

      local valid, err = validate(values, schema)
      assert.falsy(valid)
      assert.truthy(err)
      assert.are.same("string is required", err.string)
      assert.are.same("unexpected is an unknown field", err.unexpected)
    end)

    it("should validate a field against an enum", function()
      -- Success
      local values = { string = "somestring", allowed = "hello" }

      local valid, err = validate(values, schema)
      assert.falsy(err)
      assert.truthy(valid)

      -- Failure
      local values = { string = "somestring", allowed = "hello123" }

      local valid, err = validate(values, schema)
      assert.falsy(valid)
      assert.truthy(err)
      assert.are.same("\"hello123\" is not allowed. Allowed values are: \"hello\", \"world\"", err.allowed)
    end)

    it("should validate against a custom function", function()
      -- Success
      local values = { string = "somestring", custom = true }

      local valid, err = validate(values, schema)
      assert.falsy(err)
      assert.truthy(valid)

      -- Failure
      local values = { string = "somestring", custom = true, default = "not the default :O" }

      local valid, err = validate(values, schema)
      assert.falsy(valid)
      assert.truthy(err)
      assert.are.same("Nah", err.custom)
    end)

    it("should prevent immutable properties to be changed if validating a schema that will be updated", function()
      -- Success
      local values = { string = "somestring", date = 1234 }

      local valid, err = validate(values, schema)
      assert.falsy(err)
      assert.truthy(valid)

      -- Failure
      local valid, err = validate(values, schema, true)
      assert.falsy(valid)
      assert.truthy(err)
      assert.are.same("date cannot be updated", err.date)
    end)

    it("should ignore required properties if they are immutable and we are updating", function()
      local values = { string = "somestring" }

      local valid, err = validate(values, schema, true)
      assert.falsy(err)
      assert.truthy(valid)
    end)

    describe("Sub-schemas", function()

      it("should validate a property with a sub-schema", function()
        -- Success
        local values = { string = "somestring", sub_schema = { sub_field_required = "sub value" }}

        local valid, err = validate(values, schema)
        assert.falsy(err)
        assert.truthy(valid)

        -- Failure
        local values = { string = "somestring", sub_schema = { sub_field_default = "" }}

        local valid, err = validate(values, schema)
        assert.truthy(err)
        assert.falsy(valid)
      end)

    end)

  end)
end)
