local schemas = require "kong.dao.schemas_validation"
local validate = schemas.validate

require "kong.tools.ngx_stub"

describe("Schemas", function()

  -- Ok kids, today we're gonna test a custom validation schema,
  -- grab a pair of glasses, this stuff can literally explode.
  describe("#validate()", function()
    local schema = {
      string = { type = "string", required = true, immutable = true },
      table = { type = "table" },
      number = { type = "number" },
      url = { regex = "(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\\-]*[a-zA-Z0-9])\\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\\-]*[A-Za-z0-9])" },
      date = { default = 123456, immutable = true },
      allowed = { enum = { "hello", "world" }},
      boolean_val = { type = "boolean" },
      default = { default = function(t)
                              assert.truthy(t)
                              return "default"
                            end },
      custom = { func = function(v, t)
                          if v then
                            if t.default == "test_custom_func" then
                              return true
                            else
                              return false, "Nah"
                            end
                          else
                            return true
                          end
                        end }
    }

    it("should confirm a valid entity is valid", function()
      local values = { string = "mockbin entity", url = "mockbin.com" }

      local valid, err = validate(values, schema)
      assert.falsy(err)
      assert.truthy(valid)
    end)

    describe("[required]", function()
      it("should invalidate entity if required property is missing", function()
        local values = { url = "mockbin.com" }

        local valid, err = validate(values, schema)
        assert.falsy(valid)
        assert.truthy(err)
        assert.are.same("string is required", err.string)
      end)
    end)

    describe("[type]", function()
      it("should validate the type of a property if it has a type field", function()
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

      -- Failure
      local values = { string = 1, table = { foo = "bar" }}

      local valid, err = validate(values, schema)
      assert.falsy(valid)
      assert.truthy(err)
      assert.are.same("string is not a string", err.string)

      -- Success
      local values = { string = "foo", number = 10 }

      local valid, err = validate(values, schema)
      assert.falsy(err)
      assert.truthy(valid)

      -- Success
      local values = { string = "foo", number = "10" }

      local valid, err = validate(values, schema)
      assert.falsy(err)
      assert.truthy(valid)
      assert.are.same("number", type(values.number))

       -- Success
      local values = { string = "foo", boolean_val = true }

      local valid, err = validate(values, schema)
      assert.falsy(err)
      assert.truthy(valid)
      assert.are.same("boolean", type(values.boolean_val))

      -- Success
      local values = { string = "foo", boolean_val = "true" }

      local valid, err = validate(values, schema)
      assert.falsy(err)
      assert.truthy(valid)
    end)

    it("should return error when an invalid boolean value is passed", function()
      local values = { string = "test", boolean_val = "ciao" }

      local valid, err = validate(values, schema)
      assert.falsy(valid)
      assert.truthy(err)
      assert.are.same("boolean_val is not a boolean", err.boolean_val)
    end)

    it("should not return an error when a true boolean value is passed", function()
      local values = { string = "test", boolean_val = true }

      local valid, err = validate(values, schema)
      assert.falsy(err)
      assert.truthy(valid)
    end)

    it("should not return an error when a false boolean value is passed", function()
      local values = { string = "test", boolean_val = false }

      local valid, err = validate(values, schema)
      assert.falsy(err)
      assert.truthy(valid)
    end)

    it("should consider `id` and `timestamp` as types", function()
      local s = { id = { type = "id" } }

      local values = { id = "123" }

      local valid, err = validate(values, s)
      assert.falsy(err)
      assert.truthy(valid)
    end)

    it("should consider `array` as a type", function()
      local s = { array = { type = "array" } }

      -- Success
      local values = { array = {"hello", "world"} }

      local valid, err = validate(values, s)
      assert.True(valid)
      assert.falsy(err)

      -- Failure
      local values = { array = {hello="world"} }

      local valid, err = validate(values, s)
      assert.False(valid)
      assert.truthy(err)
      assert.equal("array is not a array", err.array)
    end)

    describe("[aliases]", function()
      it("should not return an error when a `number` is passed as a string", function()
        local values = { string = "test", number = "10" }

        local valid, err = validate(values, schema)
        assert.falsy(err)
        assert.truthy(valid)
        assert.same("number", type(values.number))
      end)

      it("should not return an error when a `boolean` is passed as a string", function()
        local values = { string = "test", boolean_val = "false" }

        local valid, err = validate(values, schema)
        assert.falsy(err)
        assert.truthy(valid)
        assert.same("boolean", type(values.boolean_val))
      end)

      it("should alias a string to `array`", function()
        local s = { array = { type = "array" } }

        -- It should also strip the resulting strings
        local values = { array = "hello, world" }

        local valid, err = validate(values, s)
        assert.True(valid)
        assert.falsy(err)
        assert.same({"hello", "world"}, values.array)
      end)
    end)
  end)

    describe("[default]", function()
      it("should set default values if those are variables or functions specified in the validator", function()
        -- Variables
        local values = { string = "mockbin entity", url = "mockbin.com" }

        local valid, err = validate(values, schema)
        assert.falsy(err)
        assert.truthy(valid)
        assert.are.same(123456, values.date)

        -- Functions
        local values = { string = "mockbin entity", url = "mockbin.com" }

        local valid, err = validate(values, schema)
        assert.falsy(err)
        assert.truthy(valid)
        assert.are.same("default", values.default)
      end)

      it("should override default values if specified", function()
        -- Variables
        local values = { string = "mockbin entity", url = "mockbin.com", date = 654321 }

        local valid, err = validate(values, schema)
        assert.falsy(err)
        assert.truthy(valid)
        assert.are.same(654321, values.date)

        -- Functions
        local values = { string = "mockbin entity", url = "mockbin.com", default = "abcdef" }

        local valid, err = validate(values, schema)
        assert.falsy(err)
        assert.truthy(valid)
        assert.are.same("abcdef", values.default)
      end)

    end)

    describe("[regex]", function()
      it("should validate a field against a regex", function()
        local values = { string = "mockbin entity", url = "mockbin_!" }

        local valid, err = validate(values, schema)
        assert.falsy(valid)
        assert.truthy(err)
        assert.are.same("url has an invalid value", err.url)
      end)
    end)

    describe("[enum]", function()
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
    end)

    describe("[func]", function()
      it("should validate a field against a custom function", function()
        -- Success
        local values = { string = "somestring", custom = true, default = "test_custom_func" }

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
    end)

    describe("[immutable]", function()
      it("should prevent immutable properties to be changed if validating a schema that will be updated", function()
        -- Success
        local values = { string = "somestring", date = 1234 }

        local valid, err = validate(values, schema)
        assert.falsy(err)
        assert.truthy(valid)

        -- Failure
        local valid, err = validate(values, schema, {is_update = true})
        assert.falsy(valid)
        assert.truthy(err)
        assert.are.same("date cannot be updated", err.date)
      end)

      it("should ignore required properties if they are immutable and we are updating", function()
        local values = { string = "somestring" }

        local valid, err = validate(values, schema, {is_update = true})
        assert.falsy(err)
        assert.truthy(valid)
      end)
    end)

    describe("[dao_insert_value]", function()
      local schema = {
        string = { type = "string"},
        id = { type = "id", dao_insert_value = true },
        timestamp = { type = "timestamp", dao_insert_value = true }
      }

      it("should call a given function when encountering a field with `dao_insert_value`", function()
        local values = { string = "hello", id = "0000" }

        local valid, err = validate(values, schema, { dao_insert = function(field)
          if field.type == "id" then
            return "1234"
          elseif field.type == "timestamp" then
            return 0000
          end
        end })
        assert.falsy(err)
        assert.True(valid)
        assert.equal("1234", values.id)
        assert.equal(0000, values.timestamp)
        assert.equal("hello", values.string)
      end)

      it("should not raise any error if the function is not given", function()
        local values = { string = "hello", id = "0000" }

        local valid, err = validate(values, schema, { dao_insert = true }) -- invalid type
        assert.falsy(err)
        assert.True(valid)
        assert.equal("0000", values.id)
        assert.equal("hello", values.string)
        assert.falsy(values.timestamp)
      end)

    end)

    it("should return error when unexpected values are included in the schema", function()
      local values = { string = "mockbin entity", url = "mockbin.com", unexpected = "abcdef" }

      local valid, err = validate(values, schema)
      assert.falsy(valid)
      assert.truthy(err)
    end)

    it("should be able to return multiple errors at once", function()
      local values = { url = "mockbin.com", unexpected = "abcdef" }

      local valid, err = validate(values, schema)
      assert.falsy(valid)
      assert.truthy(err)
      assert.are.same("string is required", err.string)
      assert.are.same("unexpected is an unknown field", err.unexpected)
    end)

    it("should not check a custom function if a `required` condition is false already", function()
      local f = function() error("should not be called") end -- cannot use a spy which changes the type to table
      local schema = { property = { required = true, func = f } }

      assert.has_no_errors(function()
        local valid, err = validate({}, schema)
        assert.False(valid)
        assert.are.same("property is required", err.property)
      end)
    end)

    describe("Sub-schemas", function()
      -- To check wether schema_from_function was called, we will simply use booleans because
      -- busted's spy methods create tables and metatable magic, but the validate() function
      -- only callse v.schema if the type is a function. Which is not the case with a busted spy.
      local called, called_with
      local schema_from_function = function(t)
                                     called = true
                                     called_with = t

                                     if t.error_loading_sub_sub_schema then
                                       return nil, "Error loading the sub-sub-schema"
                                     end

                                     return { sub_sub_field_required = { required = true } }
                                   end
      local nested_schema = {
        some_required = { required = true },
        sub_schema = {
          type = "table",
          schema = {
            sub_field_required = { required = true },
            sub_field_default = { default = "abcd" },
            sub_field_number = { type = "number" },
            error_loading_sub_sub_schema = {}
          }
        }
      }

      it("should validate a property with a sub-schema", function()
        -- Success
        local values = { some_required = "somestring", sub_schema = { sub_field_required = "sub value" }}

        local valid, err = validate(values, nested_schema)
        assert.falsy(err)
        assert.truthy(valid)
        assert.are.same("abcd", values.sub_schema.sub_field_default)

        -- Failure
        local values = { some_required = "somestring", sub_schema = { sub_field_default = "" }}

        local valid, err = validate(values, nested_schema)
        assert.truthy(err)
        assert.falsy(valid)
        assert.are.same("sub_field_required is required", err["sub_schema.sub_field_required"])
      end)

      it("should validate a property with a sub-schema from a function", function()
        nested_schema.sub_schema.schema.sub_sub_schema = { schema = schema_from_function }

        -- Success
        local values = { some_required = "somestring", sub_schema = {
                                                        sub_field_required = "sub value",
                                                        sub_sub_schema = { sub_sub_field_required = "test" }
                                                       }}

        local valid, err = validate(values, nested_schema)
        assert.falsy(err)
        assert.truthy(valid)

        -- Failure
        local values = { some_required = "somestring", sub_schema = {
                                                        sub_field_required = "sub value",
                                                        sub_sub_schema = {}
                                                       }}

        local valid, err = validate(values, nested_schema)
        assert.truthy(err)
        assert.falsy(valid)
        assert.are.same("sub_sub_field_required is required", err["sub_schema.sub_sub_schema.sub_sub_field_required"])
      end)

      it("should call the schema function with the actual parent t table of the subschema", function()
        local values = { some_required = "somestring", sub_schema = {
                                                        sub_field_default = "abcd",
                                                        sub_field_required = "sub value",
                                                        sub_sub_schema = { sub_sub_field_required = "test" }
                                                      }}

        local valid, err = validate(values, nested_schema)
        assert.falsy(err)
        assert.truthy(valid)
        assert.True(called)
        assert.are.same(values.sub_schema, called_with)
      end)

      it("should retrieve errors when cannot load schema from function", function()
        local values = { some_required = "somestring", sub_schema = {
                                                        sub_field_default = "abcd",
                                                        sub_field_required = "sub value",
                                                        error_loading_sub_sub_schema = true,
                                                        sub_sub_schema = { sub_sub_field_required = "test" }
                                                      }}

        local valid, err = validate(values, nested_schema)
        assert.truthy(err)
        assert.falsy(valid)
        assert.are.same("Error loading the sub-sub-schema", err["sub_schema.sub_sub_schema"])
      end)

      it("should instanciate a sub-value if sub-schema has a `default` value and do that before `required`", function()
        local function validate_value(value)
          if not value.some_property then
            return false, "value.some_property must not be empty"
          end
          return true
        end

        local schema = {
          value = { type = "table", schema = {some_property={default="hello"}}, func = validate_value, required = true }
        }

        local obj = {}
        local valid, err = validate(obj, schema)
        assert.falsy(err)
        assert.True(valid)
        assert.are.same("hello", obj.value.some_property)
      end)

      it("should mark a value required if sub-schema has a `required`", function()
        local schema = {
          value = { type = "table", schema = {some_property={required=true}} }
        }

        local obj = {}
        local valid, err = validate(obj, schema)
        assert.truthy(err)
        assert.False(valid)
        assert.are.same("value.some_property is required", err.value)
      end)

    end)
  end)
end)
