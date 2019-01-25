local schemas = require "kong.dao.schemas_validation"
local validate_entity = schemas.validate_entity

--require "kong.tools.ngx_stub"

describe("Schemas", function()

  -- Ok kids, today we're gonna test a custom validation schema,
  -- grab a pair of glasses, this stuff can literally explode.
  describe("#validate_entity()", function()
    local schema = {
      fields = {
        string = { type = "string", required = true, immutable = true},
        table = {type = "table"},
        number = {type = "number"},
        timestamp = {type = "timestamp"},
        url = {regex = "^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\\-]*[a-zA-Z0-9])\\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\\-]*[A-Za-z0-9])$"},
        date = {default = 123456, immutable = true},
        allowed = {enum = {"hello", "world"}},
        boolean_val = {type = "boolean"},
        endpoint = { type = "url" },
        enum_array = { type = "array", enum = { "hello", "world" }},
        default = {default = function(t)
                                assert.truthy(t)
                                return "default"
                              end},
        custom = {func = function(v, t)
                            if v then
                              if t.default == "test_custom_func" then
                                return true
                              else
                                return false, "Nah"
                              end
                            else
                              return true
                            end
                          end}
      }
    }

    it("should confirm a valid entity is valid", function()
      local values = {string = "example entity", url = "example.com"}

      local valid, err = validate_entity(values, schema)
      assert.falsy(err)
      assert.True(valid)
    end)

    describe("[required]", function()
      it("should invalidate entity if required property is missing", function()
        local values = {url = "example.com"}

        local valid, err = validate_entity(values, schema)
        assert.False(valid)
        assert.truthy(err)
        assert.are.same("string is required", err.string)
      end)
      it("errors if required property is set to ngx.null", function()
        local values = { string = ngx.null }

        local ok, err = validate_entity(values, schema)
        assert.falsy(ok)
        assert.equal("string is required", err.string)
      end)
    end)

    describe("[string]", function()
      it("should trim whitespace from value with no trim_whitespace property set", function()
        local values = {string = " kong "}

        local valid, err = validate_entity(values, schema)
        assert.True(valid)
        assert.falsy(err)
        assert.are.same("kong", values.string)
      end)
      it("should trim whitespace from value with trim_whitespace = true", function()
        local trim_schema = {
          fields = {
            string = { type = "string", trim_whitespace = true},
          }
        }

        local values = {string = " kong "}

        local valid, err = validate_entity(values, trim_schema)
        assert.True(valid)
        assert.falsy(err)
        assert.are.same("kong", values.string)
      end)
      it("should not trim whitespace from value with trim_whitespace = false", function()
        local notrim_schema = {
          fields = {
            string = { type = "string", trim_whitespace = false},
          }
        }

        local values = {string = " kong "}

        local valid, err = validate_entity(values, notrim_schema)
        assert.True(valid)
        assert.falsy(err)
        assert.are.same(" kong ", values.string)
      end)
    end)

    describe("[type]", function()
      --[]
      it("should validate the type of a property if it has a type field", function()
      -- Failure
      local values = {string = "foo", table = "bar"}

      local valid, err = validate_entity(values, schema)
      assert.False(valid)
      assert.truthy(err)
      assert.are.same("table is not a table", err.table)

      -- Success
      local values = {string = "foo", table = {foo = "bar"}}

      local valid, err = validate_entity(values, schema)
      assert.falsy(err)
      assert.True(valid)

      -- Failure
      local values = {string = 1, table = {foo = "bar"}}

      local valid, err = validate_entity(values, schema)
      assert.False(valid)
      assert.truthy(err)
      assert.are.same("string is not a string", err.string)

      -- Success
      local values = {string = "foo", number = 10}

      local valid, err = validate_entity(values, schema)
      assert.falsy(err)
      assert.True(valid)

      -- Success
      local values = {string = "foo", number = "10"}

      local valid, err = validate_entity(values, schema)
      assert.falsy(err)
      assert.truthy(valid)
      assert.are.same("number", type(values.number))

       -- Success
      local values = {string = "foo", boolean_val = true}

      local valid, err = validate_entity(values, schema)
      assert.falsy(err)
      assert.truthy(valid)
      assert.are.same("boolean", type(values.boolean_val))

      -- Success
      local values = {string = "foo", boolean_val = "true"}

      local valid, err = validate_entity(values, schema)
      assert.falsy(err)
      assert.truthy(valid)

      -- Failure
      local values = {string = "foo",  endpoint = ""}

      local valid, err = validate_entity(values, schema)
      assert.falsy(valid)
      assert.truthy(err)
      assert.are.equal("endpoint is not a url", err.endpoint)

      -- Failure
      local values = {string = "foo",  endpoint = "asdasd"}

      local valid, err = validate_entity(values, schema)
      assert.falsy(valid)
      assert.truthy(err)

      -- Success
      local values = {string = "foo",  endpoint = "http://google.com"}

      local valid, err = validate_entity(values, schema)
      assert.truthy(valid)
      assert.falsy(err)

      -- Success
      local values = {string = "foo",  endpoint = "http://google.com/"}

      local valid, err = validate_entity(values, schema)
      assert.truthy(valid)
      assert.falsy(err)

      -- Success
      local values = {string = "foo",  endpoint = "http://google.com/hello/?world=asd"}

      local valid, err = validate_entity(values, schema)
      assert.truthy(valid)
      assert.falsy(err)
    end)

    it("should not crash when an array has invalid contents (regression for #3144)", function()
      local values = { enum_array = 5 }

      assert.has_no_errors(function()
        local valid, err = validate_entity(values, schema)
        assert.falsy(valid)
        assert.truthy(err)
        assert.are.same("enum_array is not an array", err.enum_array)
      end)
    end)

    it("should return error when an invalid boolean value is passed", function()
      local values = {string = "test", boolean_val = "ciao"}

      local valid, err = validate_entity(values, schema)
      assert.falsy(valid)
      assert.truthy(err)
      assert.are.same("boolean_val is not a boolean", err.boolean_val)
    end)

    it("should not return an error when a true boolean value is passed", function()
      local values = {string = "test", boolean_val = true}

      local valid, err = validate_entity(values, schema)
      assert.falsy(err)
      assert.truthy(valid)
    end)

    it("should not return an error when a false boolean value is passed", function()
      local values = {string = "test", boolean_val = false}

      local valid, err = validate_entity(values, schema)
      assert.falsy(err)
      assert.truthy(valid)
    end)

    it("should consider `id` as a type", function()
      local s = {
        fields = {
          id = {type = "id"}
        }
      }

      local values = {id = "123"}

      local valid, err = validate_entity(values, s)
      assert.falsy(err)
      assert.truthy(valid)
    end)

    it("should consider `timestamp` as a type", function()
      local s = {
        fields = {
          created_at = {type = "timestamp"}
        }
      }

      local values = {created_at = "123"}

      local valid, err = validate_entity(values, s)
      assert.falsy(err)
      assert.truthy(valid)
    end)

    it("should consider `array` as a type", function()
      local s = {
        fields = {
          array = {type = "array"}
        }
      }

      -- Success
      local values = {array = {"hello", "world"}}

      local valid, err = validate_entity(values, s)
      assert.True(valid)
      assert.falsy(err)

      -- Failure
      local values = {array = {hello = "world"}}

      local valid, err = validate_entity(values, s)
      assert.False(valid)
      assert.truthy(err)
      assert.equal("array is not an array", err.array)
    end)

    describe("[aliases]", function()
      it("should not return an error when a `number` is passed as a string", function()
        local values = {string = "test", number = "10"}

        local valid, err = validate_entity(values, schema)
        assert.falsy(err)
        assert.truthy(valid)
        assert.same("number", type(values.number))
      end)

      it("should not return an error when a `boolean` is passed as a string", function()
        local values = {string = "test", boolean_val = "false"}

        local valid, err = validate_entity(values, schema)
        assert.falsy(err)
        assert.truthy(valid)
        assert.same("boolean", type(values.boolean_val))
      end)

      it("should not return an error when a `timestamp` is passed as a string", function()
        local values = {string = "test", timestamp = "123"}

        local valid, err = validate_entity(values, schema)
        assert.falsy(err)
        assert.truthy(valid)
        assert.same("number", type(values.timestamp))
      end)

      it("should return an error when a `timestamp` is not a number", function()
        local values = {string = "test", timestamp = "just a string"}

        local valid, err = validate_entity(values, schema)
        assert.falsy(valid)
        assert.are.same("timestamp is not a timestamp", err.timestamp)
      end)

      it("should return an error when a `timestamp` is a negative number", function()
        local values = {string = "test", timestamp = "-123"}

        local valid, err = validate_entity(values, schema)
        assert.falsy(valid)
        assert.are.same("timestamp is not a timestamp", err.timestamp)
      end)

      it("should alias a string to `array`", function()
        local s = {
          fields = {
            array = {type = "array"}
          }
        }

        -- It should also strip the resulting strings
        local values = { array = "hello, world" }

        local valid, err = validate_entity(values, s)
        assert.True(valid)
        assert.falsy(err)
        assert.same({"hello", "world"}, values.array)
      end)

      it("preserves escaped commas in comma-separated arrays", function()
        -- Note: regression test for arrays of PCRE URIs:
        -- https://github.com/Kong/kong/issues/2780
        local s = {
          fields = {
            array = { type = "array" }
          }
        }

        local values = {
          array = [[hello\, world,goodbye world\,,/hello/\d{1\,3}]]
        }

        local valid, err = validate_entity(values, s)
        assert.True(valid)
        assert.falsy(err)
        assert.same({ "hello, world", "goodbye world,", [[/hello/\d{1,3}]] },
                    values.array)
      end)
    end)
  end)

    describe("[default]", function()
      it("should set default values if those are variables or functions specified in the validator", function()
        -- Variables
        local values = {string = "example entity", url = "example.com"}

        local valid, err = validate_entity(values, schema)
        assert.falsy(err)
        assert.truthy(valid)
        assert.are.same(123456, values.date)

        -- Functions
        local values = {string = "example entity", url = "example.com"}

        local valid, err = validate_entity(values, schema)
        assert.falsy(err)
        assert.truthy(valid)
        assert.are.same("default", values.default)
      end)

      it("should override default values if specified", function()
        -- Variables
        local values = {string = "example entity", url = "example.com", date = 654321}

        local valid, err = validate_entity(values, schema)
        assert.falsy(err)
        assert.truthy(valid)
        assert.are.same(654321, values.date)

        -- Functions
        local values = {string = "example entity", url = "example.com", default = "abcdef"}

        local valid, err = validate_entity(values, schema)
        assert.falsy(err)
        assert.truthy(valid)
        assert.are.same("abcdef", values.default)
      end)

      it("sets to default when a field is given ngx.null", function()
        local values = { string = "foo", default = ngx.null }

        local ok, err = validate_entity(values, schema)
        assert.falsy(err)
        assert.is_true(ok)
        assert.equal("default", values.default)
      end)
    end)

    describe("[regex]", function()
      it("should validate a field against a regex", function()
        local values = {string = "example entity", url = "example_!"}

        local valid, err = validate_entity(values, schema)
        assert.falsy(valid)
        assert.truthy(err)
        assert.are.same("url has an invalid value", err.url)
      end)
    end)

    describe("[enum]", function()
      it("should validate a field against an enum", function()
        -- Success
        local values = {string = "somestring", allowed = "hello"}

        local valid, err = validate_entity(values, schema)
        assert.falsy(err)
        assert.truthy(valid)

        -- Failure
        local values = {string = "somestring", allowed = "hello123"}

        local valid, err = validate_entity(values, schema)
        assert.falsy(valid)
        assert.truthy(err)
        assert.are.same("\"hello123\" is not allowed. Allowed values are: \"hello\", \"world\"", err.allowed)
      end)

      it("should validate an enum into an array", function()
        -- Failure
        local values = {string = "somestring", enum_array = "hello1"}

        local valid, err = validate_entity(values, schema)
        assert.truthy(err)
        assert.falsy(valid)
        assert.are.same("\"hello1\" is not allowed. Allowed values are: \"hello\", \"world\"", err.enum_array)

        -- Failure
        local values = {string = "somestring", enum_array = {"hello1"}}

        local valid, err = validate_entity(values, schema)
        assert.truthy(err)
        assert.falsy(valid)
        assert.are.same("\"hello1\" is not allowed. Allowed values are: \"hello\", \"world\"", err.enum_array)

        -- Success
        local values = {string = "somestring", enum_array = {"hello"}}

        local valid, err = validate_entity(values, schema)
        assert.falsy(err)
        assert.truthy(valid)

        -- Success
        local values = {string = "somestring", enum_array = {"hello", "world"}}

        local valid, err = validate_entity(values, schema)
        assert.falsy(err)
        assert.truthy(valid)

        -- Failure
        local values = {string = "somestring", enum_array = {"hello", "world", "another"}}

        local valid, err = validate_entity(values, schema)
        assert.truthy(err)
        assert.falsy(valid)
        assert.are.same("\"another\" is not allowed. Allowed values are: \"hello\", \"world\"", err.enum_array)

        -- Success
        local values = {string = "somestring", enum_array = {}}

        local valid, err = validate_entity(values, schema)
        assert.falsy(err)
        assert.truthy(valid)
      end)
    end)

    describe("[func]", function()
      it("should validate a field against a custom function", function()
        -- Success
        local values = {string = "somestring", custom = true, default = "test_custom_func"}

        local valid, err = validate_entity(values, schema)
        assert.falsy(err)
        assert.truthy(valid)

        -- Failure
        local values = {string = "somestring", custom = true, default = "not the default :O"}

        local valid, err = validate_entity(values, schema)
        assert.falsy(valid)
        assert.truthy(err)
        assert.are.same("Nah", err.custom)
      end)
      it("is called with arg1 'nil' when given ngx.null", function()
        spy.on(schema.fields.custom, "func")

        local values = { string = "foo", custom = ngx.null }

        local ok, err = validate_entity(values, schema)
        assert.falsy(err)
        assert.is_true(ok)
        assert.is_nil(values.custom)
        assert.spy(schema.fields.custom.func).was_called_with(nil, values, "custom")
      end)
    end)

    it("should return error when unexpected values are included in the schema", function()
      local values = {string = "example entity", url = "example.com", unexpected = "abcdef"}

      local valid, err = validate_entity(values, schema)
      assert.falsy(valid)
      assert.truthy(err)
    end)

    it("should be able to return multiple errors at once", function()
      local values = {url = "example.com", unexpected = "abcdef"}

      local valid, err = validate_entity(values, schema)
      assert.falsy(valid)
      assert.truthy(err)
      assert.are.same("string is required", err.string)
      assert.are.same("unexpected is an unknown field", err.unexpected)
    end)

    it("should not check a custom function if a `required` condition is false already", function()
      local f = function() error("should not be called") end -- cannot use a spy which changes the type to table
      local schema = {
        fields = {
          property = {required = true, func = f}
        }
      }

      assert.has_no_errors(function()
        local valid, err = validate_entity({}, schema)
        assert.False(valid)
        assert.are.same("property is required", err.property)
      end)
    end)

    describe("Sub-schemas", function()
      -- To check wether schema_from_function was called, we will simply use booleans because
      -- busted's spy methods create tables and metatable magic, but the validate_entity() function
      -- only callse v.schema if the type is a function. Which is not the case with a busted spy.
      local called, called_with
      local schema_from_function = function(t)
                                     called = true
                                     called_with = t

                                     if t.error_loading_sub_sub_schema then
                                       return nil, "Error loading the sub-sub-schema"
                                     end

                                     return {fields = {sub_sub_field_required = {required = true}}}
                                   end
      local nested_schema = {
        fields = {
          some_required = { required = true },
          sub_schema = {
            type = "table",
            schema = {
              fields = {
                sub_field_required = {required = true},
                sub_field_default = {default = "abcd"},
                sub_field_number = {type = "number"},
                error_loading_sub_sub_schema = {}
              }
            }
          }
        }
      }

      it("should validate a property with a sub-schema", function()
        -- Success
        local values = { some_required = "somestring", sub_schema = {sub_field_required = "sub value"}}

        local valid, err = validate_entity(values, nested_schema)
        assert.falsy(err)
        assert.truthy(valid)
        assert.are.same("abcd", values.sub_schema.sub_field_default)

        -- Failure
        local values = {some_required = "somestring", sub_schema = {sub_field_default = ""}}

        local valid, err = validate_entity(values, nested_schema)
        assert.truthy(err)
        assert.falsy(valid)
        assert.are.same("sub_field_required is required", err["sub_schema.sub_field_required"])
      end)

      it("should validate a property with a sub-schema from a function", function()
        nested_schema.fields.sub_schema.schema.fields.sub_sub_schema = {schema = schema_from_function}

        -- Success
        local values = {some_required = "somestring", sub_schema = {
                                                        sub_field_required = "sub value",
                                                        sub_sub_schema = {sub_sub_field_required = "test"}
                                                       }}

        local valid, err = validate_entity(values, nested_schema)
        assert.falsy(err)
        assert.truthy(valid)

        -- Failure
        local values = {some_required = "somestring", sub_schema = {
                                                        sub_field_required = "sub value",
                                                        sub_sub_schema = {}
                                                       }}

        local valid, err = validate_entity(values, nested_schema)
        assert.truthy(err)
        assert.falsy(valid)
        assert.are.same("sub_sub_field_required is required", err["sub_schema.sub_sub_schema.sub_sub_field_required"])
      end)

      it("should call the schema function with the actual parent t table of the subschema", function()
        local values = {some_required = "somestring", sub_schema = {
                                                        sub_field_default = "abcd",
                                                        sub_field_required = "sub value",
                                                        sub_sub_schema = {sub_sub_field_required = "test"}
                                                      }}

        local valid, err = validate_entity(values, nested_schema)
        assert.falsy(err)
        assert.truthy(valid)
        assert.True(called)
        assert.are.same(values.sub_schema, called_with)
      end)

      it("should retrieve errors when cannot load schema from function", function()
        local values = {some_required = "somestring", sub_schema = {
                                                        sub_field_default = "abcd",
                                                        sub_field_required = "sub value",
                                                        error_loading_sub_sub_schema = true,
                                                        sub_sub_schema = {sub_sub_field_required = "test"}
                                                      }}

        local valid, err = validate_entity(values, nested_schema)
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
          fields = {
            value = {type = "table", schema = {fields = {some_property = {default = "hello"}}}, func = validate_value, required = true}
          }
        }

        local obj = {}
        local valid, err = validate_entity(obj, schema)
        assert.falsy(err)
        assert.True(valid)
        assert.are.same("hello", obj.value.some_property)
      end)

      it("should mark a value required if sub-schema has a `required`", function()
        local schema = {
          fields = {
            value = {type = "table", schema = {fields = {some_property={required=true}}}}
          }
        }

        local obj = {}
        local valid, err = validate_entity(obj, schema)
        assert.truthy(err)
        assert.False(valid)
        assert.are.same("value.some_property is required", err.value)
      end)

      it("should work with flexible schemas", function()
        local schema = {
          fields = {
            flexi = { type = "table",
              schema = {
                flexible = true,
                fields = {
                  name = {type = "string"},
                  age = {type = "number"}
                }
              }
            }
          }
        }

        local obj = {
          flexi = {
            somekey = {
              name = "Mark",
              age = 12
            }
          }
        }

        local valid, err = validate_entity(obj, schema)
        assert.falsy(err)
        assert.True(valid)

        assert.are.same({flexi = {
          somekey = {
            name = "Mark",
            age = 12
          }
        }}, obj)

        obj = {
          flexi = {
            somekey = {
              name = "Mark",
              age = 12
            },
            hello = {
              name = "Mark2",
              age = 13
            }
          }
        }

        valid, err = validate_entity(obj, schema)
        assert.falsy(err)
        assert.True(valid)

        assert.are.same({flexi = {
          somekey = {
            name = "Mark",
            age = 12
          },
          hello = {
            name = "Mark2",
            age = 13
          }
        }}, obj)
      end)

      it("should return proper errors with a flexible schema", function()
        local schema = {
          fields = {
            flexi = { type = "table",
              schema = {
                flexible = true,
                fields = {
                  name = {type = "string"},
                  age = {type = "number"}
                }
              }
            }
          }
        }

        local obj = {
          flexi = {
            somekey = {
              name = "Mark",
              age = "hello"
            }
          }
        }

        local valid, err = validate_entity(obj, schema)
        assert.truthy(err)
        assert.falsy(valid)
        assert.are.same("age is not a number", err["flexi.somekey.age"])
      end)

      it("should return proper errors with a flexible schema an an unknown field", function()
        local schema = {
          fields = {
            flexi = { type = "table",
              schema = {
                flexible = true,
                fields = {
                  name = {type = "string"},
                  age = {type = "number"}
                }
              }
            }
          }
        }

        local obj = {
          flexi = {
            somekey = {
              name = "Mark",
              age = 12,
              asd = "hello"
            }
          }
        }

        local valid, err = validate_entity(obj, schema)
        assert.truthy(err)
        assert.falsy(valid)
        assert.are.same("asd is an unknown field", err["flexi.somekey.asd"])
      end)

      it("should return proper errors with a flexible schema with two keys and an unknown field", function()
        local schema = {
          fields = {
            flexi = { type = "table",
              schema = {
                flexible = true,
                fields = {
                  name = {type = "string"},
                  age = {type = "number"}
                }
              }
            }
          }
        }

        local obj = {
          flexi = {
            somekey = {
              name = "Mark"
            },
            somekey2 = {
              name = "Mark",
              age = 12,
              asd = "hello"
            }
          }
        }

        local valid, err = validate_entity(obj, schema)
        assert.truthy(err)
        assert.falsy(valid)
        assert.are.same("asd is an unknown field", err["flexi.somekey2.asd"])
      end)

      it("errors if required sub-schema is given ngx.null", function()
        local values = { some_required = "foo", sub_schema = ngx.null }

        local ok, err = validate_entity(values, nested_schema)
        assert.falsy(ok)
        assert.same({
          ["sub_schema"] = "sub_schema.sub_field_required is required",
          ["sub_schema.sub_field_required"] = "sub_field_required is required",
          ["sub_schema.sub_sub_schema"] = "sub_sub_schema.sub_sub_field_required is required",
        }, err)
      end)

      it("gives NULL to sub-schema if given ngx.null in update", function()
        local values = { some_required = "foo", sub_schema = ngx.null }

        local ok, err = validate_entity(values, nested_schema, { update = true })
        assert.falsy(err)
        assert.is_true(ok)
        assert.equal(ngx.null, values.sub_schema)
      end)

      it("errors if required sub-schema is given ngx.null in a full update", function()
        local values = { some_required = "foo", sub_schema = ngx.null }

        local ok, err = validate_entity(values, nested_schema, { update = true, full_update = true })
        assert.falsy(ok)
        assert.same({
          ["sub_schema"] = "sub_schema.sub_field_required is required",
          ["sub_schema.sub_field_required"] = "sub_field_required is required",
          ["sub_schema.sub_sub_schema"] = "sub_sub_schema.sub_sub_field_required is required",
        }, err)
      end)
    end)

    describe("[update] (partial)", function()
      it("should ignore required properties and defaults if we are updating because the entity might be partial", function()
        local values = {}

        local valid, err = validate_entity(values, schema, {update = true})
        assert.falsy(err)
        assert.True(valid)
        assert.falsy(values.default)
        assert.falsy(values.date)
      end)

      it("should still validate set properties", function()
        local values = {string = 123}

        local valid, err = validate_entity(values, schema, {update = true})
        assert.False(valid)
        assert.equal("string is not a string", err.string)
      end)

      it("should ignore immutable fields if they are required", function()
        local values = {string = "somestring"}

        local valid, err = validate_entity(values, schema, {update = true})
        assert.falsy(err)
        assert.True(valid)
      end)

      it("should prevent immutable fields to be changed", function()
        -- Success
        local values = {string = "somestring", date = 5678}

        local valid, err = validate_entity(values, schema)
        assert.falsy(err)
        assert.truthy(valid)

        -- Failure
        local valid, err = validate_entity(values, schema, {update = true, old_t = {date = 1234}})
        assert.False(valid)
        assert.truthy(err)
        assert.equal("date cannot be updated", err.date)
      end)

      it("passes NULL if a field with default is given ngx.null", function()
        local values = { string = "foo", date = ngx.null }

        local ok, err = validate_entity(values, schema, { update = true })
        assert.falsy(err)
        assert.is_true(ok)
        assert.equal(ngx.null, values.date) -- DAO will handle ngx.null to 'NULL'
      end)

      it("calls 'func' with arg1 'nil' when given ngx.null", function()
        spy.on(schema.fields.custom, "func")

        local values = { string = "foo", custom = ngx.null }

        local ok, err = validate_entity(values, schema, { update = true })
        assert.falsy(err)
        assert.is_true(ok)
        assert.equal(ngx.null, values.custom)
        assert.spy(schema.fields.custom.func).was_called_with(nil, values, "custom")
      end)

      it("errors when a required field is given ngx.null", function()
        spy.on(schema.fields.custom, "func")

        local values = { string = ngx.null }

        local ok, err = validate_entity(values, schema, { update = true })
        assert.falsy(ok)
        assert.equal("string is required", err.string)
      end)
    end)

    describe("[update] (full)", function()
      it("should not ignore required properties", function()
        local values = {}

        local valid, err = validate_entity(values, schema, {update = true, full_update = true})
        assert.False(valid)
        assert.truthy(err)
        assert.equal("string is required", err.string)
      end)
      it("should complete default fields", function()
        local values = {string = "foo", date = 123456}

        local valid, err = validate_entity(values, schema, {update = true, full_update = true})
        assert.True(valid)
        assert.falsy(err)
        assert.equal("default", values.default)
      end)
      it("sets a field to its default if given ngx.null", function()
        local values = { string = "foo", date = ngx.null }

        local ok, err = validate_entity(values, schema, {update = true, full_update = true})
        assert.falsy(err)
        assert.is_true(ok)
        assert.is_number(values.date)
      end)
      it("calls 'func' with arg1 'nil' when given ngx.null", function()
        spy.on(schema.fields.custom, "func")

        local values = { string = "foo", custom = ngx.null }

        local ok, err = validate_entity(values, schema, { update = true, full_update = true })
        assert.falsy(err)
        assert.is_true(ok)
        assert.is_nil(values.custom)
        assert.spy(schema.fields.custom.func).was_called_with(nil, values, "custom")
      end)
      it("errors when a required field is given ngx.null", function()
        spy.on(schema.fields.custom, "func")

        local values = { string = ngx.null }

        local ok, err = validate_entity(values, schema, { update = true, full_update = true })
        assert.falsy(ok)
        assert.equal("string is required", err.string)
      end)
    end)
  end)
end)
