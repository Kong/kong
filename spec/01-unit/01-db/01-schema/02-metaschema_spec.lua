-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local Schema = require "kong.db.schema"
local helpers = require "spec.helpers"
local MetaSchema = require "kong.db.schema.metaschema"
local constants = require "kong.constants"

describe("metaschema", function()
  it("rejects a bad schema", function()
    local s = {
      name = "bad",
      fields = {
        { foo = "bar", },
      },
      primary_key = { "foo" },
    }
    assert.falsy(MetaSchema:validate(s))
  end)

  it("requires an array schema to have `elements`", function()
    local s = {
      name = "bad",
      primary_key = { "f" },
      fields = {
        { f = { type = "array" } }
      }
    }
    local ok, err = MetaSchema:validate(s)
    assert.falsy(ok)
    assert.match("field of type 'array' must declare 'elements'", err.f)
  end)

  it("requires an set schema to have `elements`", function()
    local s = {
      name = "bad",
      primary_key = { "f" },
      fields = {
        { f = { type = "set" } }
      }
    }
    local ok, err = MetaSchema:validate(s)
    assert.falsy(ok)
    assert.match("field of type 'set' must declare 'elements'", err.f)
  end)

  it("requires a map schema to have `keys`", function()
    local s = {
      name = "bad",
      primary_key = { "f" },
      fields = {
        { f = { type = "map", values = { type = "string" } } }
      }
    }
    local ok, err = MetaSchema:validate(s)
    assert.falsy(ok)
    assert.match("field of type 'map' must declare 'keys'", err.f)
  end)

  it("requires a map schema to have `values`", function()
    local s = {
      name = "bad",
      primary_key = { "f" },
      fields = {
        { f = { type = "map", keys = { type = "string" } } }
      }
    }
    local ok, err = MetaSchema:validate(s)
    assert.falsy(ok)
    assert.match("field of type 'map' must declare 'values'", err.f)
  end)

  it("requires a record schema to have `fields`", function()
    local s = {
      name = "bad",
      primary_key = { "f" },
      fields = {
        { f = { type = "record" } }
      }
    }
    local ok, err = MetaSchema:validate(s)
    assert.falsy(ok)
    assert.match("field of type 'record' must declare 'fields'", err.f)
  end)

  it("fields cannot be empty", function()
    local s = {
      name = "bad",
      fields = {
        {}
      },
      primary_key = { "foo" },
    }
    local ok, err = MetaSchema:validate(s)
    assert.falsy(ok)
    assert.match("field entry table is empty", err.fields)
  end)

  it("rejects an invalid entity check", function()
    local s = {
      name = "bad",
      fields = {
        { foo = { type = "number" }, },
      },
      primary_key = { "foo" },
      entity_checks = {
        foo = { "bar" },
      }
    }
    assert.falsy(MetaSchema:validate(s))
  end)

  it("validates a schema with nested records", function()
    local s = {
      name = "hello",
      primary_key = { "foo" },
      fields = {
        { foo = { type = "number" } },
        { f = {
            type = "record",
            fields = {
              { r = {
                  type = "record",
                  fields = {
                    { a = { type = "string" }, },
                    { b = { type = "number" }, } }}}}}}}}
    assert.truthy(MetaSchema:validate(s))
  end)

  it("a schema cannot be marked as legacy", function()
    local s = {
      name = "hello",
      primary_key = { "foo" },
      legacy = true,
      fields = {
        { foo = { type = "number" } } } }
    assert.falsy(MetaSchema:validate(s))

    s = {
      name = "hello",
      primary_key = { "foo" },
      legacy = 2,
      fields = {
        { foo = { type = "number" } } } }
    assert.falsy(MetaSchema:validate(s))
  end)

  it("a schema can declare a cache_key", function()
    local s = {
      name = "hello",
      primary_key = { "foo" },
      cache_key = { "foo" },
      fields = {
        { foo = { type = "number", unique = true } } } }
    assert.truthy(MetaSchema:validate(s))
  end)

  it("cache_key elements must be fields", function()
    local s = {
      name = "hello",
      primary_key = { "foo" },
      cache_key = { "foo", "bar" },
      fields = {
        { foo = { type = "number" } } } }
    assert.falsy(MetaSchema:validate(s))
  end)

  it("a field in a single-field cache_key must be unique", function()
    local s = {
      name = "hello",
      primary_key = { "foo" },
      cache_key = { "foo" },
      fields = {
        { foo = { type = "number" } } } }
    assert.falsy(MetaSchema:validate(s))
  end)

  it("fields in a composite cache_key don't need to be unique", function()
    local s = {
      name = "hello",
      primary_key = { "foo" },
      cache_key = { "foo", "bar" },
      fields = {
        { foo = { type = "number" } },
        { bar = { type = "number" } } } }
    assert.truthy(MetaSchema:validate(s))
  end)

  it("allows only one entity check per array field", function()
    local s = {
      name = "bad",
      fields = {
        { a = { type = "number" } },
        { b = { type = "number" } },
        { c = { type = "number" } },
        { d = { type = "number" } },
      },
      primary_key = { "foo" },
      entity_checks = {
        { only_one_of = { "a", "b" },
          at_least_one_of = { "c", "d" },
        },
      }
    }
    local ok, errs = MetaSchema:validate(s)
    assert.falsy(ok)
    assert.truthy(errs)
  end)

  it("accepts a function in an entity check", function()
    local s = {
      name = "bad",
      fields = {
        { a = { type = "number" } },
        { b = { type = "number" } },
      },
      primary_key = { "a" },
      entity_checks = {
        { custom_entity_check = {
            field_sources = { "a" },
            fn = function()
              return true
            end,
          }
        },
      }
    }
    local ok = MetaSchema:validate(s)
    assert.truthy(ok)
  end)

  it("demands a primary key", function()
    local s = {
      name = "bad",
      fields = {
        { foo = "bar", },
      },
    }
    local ok, errs = MetaSchema:validate(s)
    assert.falsy(ok)
    assert.truthy(errs["primary_key"])
  end)

  it("rejects a bad schema checking nested error", function()
    local s = {
      name = "bad",
      fields = {
        {
          foo = {
            type = "array",
            elements = {
              { foo = "bar", },
            }
          }
        }
      },
      primary_key = { "foo" },
    }
    assert.falsy(MetaSchema:validate(s))
  end)

  it("rejects a bad schema matching validators and types", function()
    local s = {
      name = "bad",
      fields = {
        {
          foo = {
            type = "array",
            -- will cause error because `uuid` must be used with `strings`
            elements = { type = "number", uuid = true, },
          }
        }
      },
      primary_key = { "foo" },
    }
    local ret, errs = MetaSchema:validate(s)
    assert.falsy(ret)
    assert.truthy(errs and errs["foo"])
  end)

  it("supports all Schema validators", function()
    local set = MetaSchema.get_supported_validator_set()
    for name, _ in pairs(Schema.validators) do
      assert.truthy(set[name], "'" .. name .. "' is missing from MetaSchema")
    end

    for name, _ in pairs(set) do
      local err = "'" .. name .. "' in MetaSchema is not a declared validator"
      assert.truthy(Schema.validators[name], err)
    end
  end)

  it("allows specifying an endpoint key with endpoint_key", function()
    local s = {
      name = "test",
      endpoint_key = "str",
      fields = {
        { str = { type = "string", unique = true } },
        { num = { type = "number" } },
      },
      primary_key = { "str" },
    }
    assert.truthy(MetaSchema:validate(s))
  end)

  it("endpoint_key must be a field", function()
    local s = {
      name = "test",
      endpoint_key = "bla",
      fields = {
        { str = { type = "string", unique = true } },
        { num = { type = "number" } },
      },
      primary_key = { "str" },
    }
    local ok, err = MetaSchema:validate(s)
    assert.falsy(ok)
    assert.match("value must be a field name", err.endpoint_key)
  end)

  it("ttl support can be enabled with ttl = true", function()
    local s = {
      name = "test",
      ttl = true,
      fields = {
        { str = { type = "string", unique = true } },
        { created_at = { type = "number", timestamp = true, auto = true } },
      },
      primary_key = { "str" },
    }
    assert.truthy(MetaSchema:validate(s))
  end)

  it("ttl support can be disabled with ttl = false", function()
    local s = {
      name = "test",
      ttl = false,
      fields = {
        { str = { type = "string", unique = true } },
      },
      primary_key = { "str" },
    }
    assert.truthy(MetaSchema:validate(s))
  end)

  it("ttl support can be disabled with ttl = nil", function()
    local s = {
      name = "test",
      fields = {
        { str = { type = "string", unique = true } },
        { ttl = { type = "integer" } },
      },
      primary_key = { "str" },
    }
    assert.truthy(MetaSchema:validate(s))
  end)


  it("ttl must be a boolean (true)", function()
    local s = {
      name = "test",
      ttl = "true",
      fields = {
        { str = { type = "string", unique = true } },
        { created_at = { type = "integer", timestamp = true, auto = true } },
      },
      primary_key = { "str" },
    }
    local ok, err = MetaSchema:validate(s)
    assert.falsy(ok)
    assert.match("expected a boolean", err.ttl)
  end)

  it("ttl reserves ttl as a field name", function()
    local s = {
      name = "test",
      ttl = "true",
      fields = {
        { str = { type = "string", unique = true } },
        { ttl = { type = "integer" } },
        { created_at = { type = "integer", timestamp = true, auto = true } },
      },
      primary_key = { "str" },
    }
    local ok, err = MetaSchema:validate(s)
    assert.falsy(ok)
    assert.match("ttl is a reserved field name when ttl is enabled", err.ttl)
  end)

  it("supports the unique attribute in base types", function()
    local s = {
      name = "test",
      fields = {
        { str = { type = "string", unique = true } },
        { num = { type = "number", unique = true } },
        { int = { type = "integer", unique = true } },
      },
      primary_key = { "str" },
    }
    assert.truthy(MetaSchema:validate(s))
  end)

  it("rejects the unique attribute in composite types", function()
    local s = {
      name = "test",
      fields = {
        { id  = { type = "string" } },
        { arr = { type = "array", unique = true } },
        { map = { type = "map", unique = true } },
        { rec = { type = "record", unique = true } },
        { set = { type = "set", unique = true } },
      },
      primary_key = { "id" },
    }
    local ok, err = MetaSchema:validate(s)
    assert.falsy(ok)
    assert.match("'array' cannot have attribute 'unique'", err.arr)
    assert.match("'map' cannot have attribute 'unique'", err.map)
    assert.match("'record' cannot have attribute 'unique'", err.rec)
    assert.match("'set' cannot have attribute 'unique'", err.set)
  end)

  it("a schema cannot have a field of type 'any'", function()
    local s = {
      name = "hello",
      primary_key = { "foo" },
      fields = {
        { foo = { type = "any" } } } }
    local ok, err = MetaSchema:validate(s)
    assert.falsy(ok)
    assert.match("expected one of", err.fields[1].type)
  end)

  it("accepts an 'err' field", function()
    local s = {
      name = "hello",
      primary_key = { "foo" },
      fields = {
        { foo = { type = "array", elements = {type = "string"}, eq = ngx.null, err = "cannot set value" } }
      }
    }
    assert.truthy(MetaSchema:validate(s))
  end)

  it("populates the 'table_name' field from 'name' if not supplied", function()
    local s = {
      name = "testing",
      primary_key = { "id" },
      fields = {
        { id = { type = "string", }, },
        { foo = { type = "string" }, },
      },
    }

    assert.truthy(MetaSchema:validate(s))
    local schema = Schema.new(s)

    assert.not_nil(schema.table_name)
    assert.equals("testing", schema.name)
    assert.equals("testing", schema.table_name)

    s.table_name = "explicit_table_name"
    assert.truthy(MetaSchema:validate(s))
    schema = Schema.new(s)

    assert.not_nil(schema.table_name)
    assert.equals("testing", schema.name)
    assert.equals("explicit_table_name", schema.table_name)
  end)

  describe("subschemas", function()

    it("supports declaring subschemas", function()
      local s = {
        name = "test",
        subschema_key = "str",
        fields = {
          { str = { type = "string", unique = true } },
        },
        primary_key = { "str" },
      }
      assert.truthy(MetaSchema:validate(s))
    end)

    it("subschema_key must be an existing field name", function()
      local s = {
        name = "test",
        subschema_key = "str",
        fields = {
          { str = { type = "string", unique = true } },
        },
        primary_key = { "str" },
      }

      local ok = MetaSchema:validate(s)
      assert.truthy(ok)

      local err
      s.subschema_key = "foo"
      ok, err = MetaSchema:validate(s)
      assert.falsy(ok)
      assert.match("value must be a field name", err.subschema_key)
    end)

    it("subschema_key must be a string field", function()
      local s = {
        name = "test",
        subschema_key = "num",
        fields = {
          { str = { type = "string", unique = true } },
          { num = { type = "number", unique = true } },
        },
        primary_key = { "str" },
      }
      local ok, err = MetaSchema:validate(s)
      assert.falsy(ok)
      assert.match("must be a string", err.subschema_key)
    end)

    it("schema can define abstract fields", function()
      local s = {
        name = "test",
        subschema_key = "str",
        fields = {
          { str = { type = "string", unique = true } },
          { num = { type = "number", abstract = true } },
        },
        primary_key = { "str" },
      }

      local ok = MetaSchema:validate(s)
      assert.truthy(ok)
    end)

    it("abstract composite types can be abstract within their limitations", function()
      local s = {
        name = "test",
        subschema_key = "str",
        fields = {
          { str = { type = "string", unique = true } },
          -- abstract arrays, sets and maps need their types
          -- so that strategies (postgres in particular)
          -- can build the proper types
          { arr = { type = "array", abstract = true } },
          { set = { type = "set", abstract = true } },
          { map = { type = "map", abstract = true } },
          -- abstract records don't need their fields
          -- to be declared because strategies store them as JSON
          -- (we need this property for the `config` field of Plugins)
          { rec = { type = "record", abstract = true } },
        },
        primary_key = { "str" },
      }

      local ok, err = MetaSchema:validate(s)
      assert.falsy(ok)
      assert.same({
        arr = "field of type 'array' must declare 'elements'",
        set = "field of type 'set' must declare 'elements'",
        map = "field of type 'map' must declare 'values'",
      }, err)

      s = {
        name = "test",
        subschema_key = "str",
        fields = {
          { str = { type = "string", unique = true } },
          { arr = { type = "array", elements = { type = "string" }, abstract = true } },
          { set = { type = "set", elements = { type = "string" }, abstract = true } },
          { rec = { type = "record", abstract = true } },
        },
        primary_key = { "str" },
      }

      ok = MetaSchema:validate(s)
      assert.truthy(ok)
    end)

  end)

  it("validates a value with 'eq'", function()
    assert.truthy(MetaSchema:validate({
      name = "test",
      primary_key = { "pk" },
      fields = {
        { pk = { type = "boolean", default = true, eq = true } },
      },
    }))
  end)

  it("validates the routes schema", function()
    local Routes = require("kong.db.schema.entities.routes")
    assert.truthy(MetaSchema:validate(Routes))
    Schema.new(Routes)
    -- do it a second time to show that Schema.new does not corrupt the table
    assert.truthy(MetaSchema:validate(Routes))
  end)

  it("validates the services schema", function()
    local Services = require("kong.db.schema.entities.services")
    assert.truthy(MetaSchema:validate(Services))
  end)

  pending("validates itself", function()
    -- This goes into an endless loop because the schema validator
    -- does not account for cyclic schemas at this point.
    assert.truthy(MetaSchema:validate(MetaSchema))
  end)

  it("validates transformation has transformation function specified (positive)", function()
    assert.truthy(MetaSchema:validate({
      name = "test",
      primary_key = { "test" },
      fields = {
        { test = { type = "string" } },
      },
      transformations = {
        {
          on_write = function() return true end,
        },
      },
    }))

    assert.truthy(MetaSchema:validate({
      name = "test",
      primary_key = { "test" },
      fields = {
        { test = { type = "string" } },
      },
      transformations = {
        {
          input = { "test" },
          on_write = function() return true end,
        },
      },
    }))

    assert.truthy(MetaSchema:validate({
      name = "test",
      primary_key = { "test" },
      fields = {
        { test = { type = "string" } },
      },
      transformations = {
        {
          input = { "test" },
          on_read = function() return true end,
        },
      },
    }))

    assert.truthy(MetaSchema:validate({
      name = "test",
      primary_key = { "test" },
      fields = {
        { test = { type = "string" } },
      },
      transformations = {
        {
          input = { "test" },
          on_read = function() return true end,
          on_write = function() return true end,
        },
      },
    }))
  end)

  it("validates transformation has transformation function specified (negative)", function()
    assert.falsy(MetaSchema:validate({
      name = "test",
      primary_key = { "test" },
      fields = {
        { test = { type = "string" } },
      },
      transformations = {
        {
          input = { "test" },
        },
      },
    }))
  end)

  it("validates transformation input fields exists (positive)", function()
    assert.truthy(MetaSchema:validate({
      name = "test",
      primary_key = { "test" },
      fields = {
        { test = { type = "string" } },
      },
      transformations = {
        {
          input = { "test" },
          on_write = function() return true end,
        },
      },
    }))
  end)

  it("validates transformation input fields exists (negative)", function()
    assert.falsy(MetaSchema:validate({
      name = "test",
      primary_key = { "test" },
      fields = {
        { test = { type = "string" } },
      },
      transformations = {
        {
          input = { "nonexisting" },
          on_write = function() return true end,
        },
      },
    }))
  end)

  it("validates nested transformation input fields exists (positive)", function()
    assert.truthy(MetaSchema:validate({
      name = "test",
      primary_key = { "test" },
      fields = {
        {
          test = {
            type = "record",
            fields = {
              {
                field = { type = "string" }
              },
            }
          }
        },
      },
      transformations = {
        {
          input = { "test.field" },
          on_write = function() return true end,
        },
      },
    }))
  end)

  it("validates nested transformation input fields exists (negative)", function()
    assert.falsy(MetaSchema:validate({
      name = "test",
      primary_key = { "test" },
      fields = {
        {
          test = {
            type = "record",
            fields = {
              {
                field = { type = "string" },
              },
            },
          },
        },
      },
      transformations = {
        {
          input = { "test.nonexisting" },
          on_write = function() return true end,
        },
      },
    }))

    assert.falsy(MetaSchema:validate({
      name = "test",
      primary_key = { "test" },
      fields = {
        {
          test = {
            type = "record",
            fields = {
              {
                field = { type = "string" },
              },
            },
          },
        },
      },
      transformations = {
        {
          input = { "nonexisting.field" },
          on_write = function() return true end,
        },
      },
    }))
  end)

  it("validates transformation needs fields exists (positive)", function()
    assert.truthy(MetaSchema:validate({
      name = "test",
      primary_key = { "test" },
      fields = {
        { test = { type = "string" } },
      },
      transformations = {
        {
          input = { "test" },
          needs = { "test" },
          on_write = function() return true end,
        },
      },
    }))
  end)

  it("validates transformation needs fields exists (negative)", function()
    assert.falsy(MetaSchema:validate({
      name = "test",
      primary_key = { "test" },
      fields = {
        { test = { type = "string" } },
      },
      transformations = {
        {
          input = { "test" },
          needs = { "nonexisting" },
          on_write = function() return true end,
        },
      },
    }))
  end)

  it("validates nested transformation needs fields exists (positive)", function()
    assert.truthy(MetaSchema:validate({
      name = "test",
      primary_key = { "test" },
      fields = {
        {
          test = {
            type = "record",
            fields = {
              {
                field = { type = "string" }
              },
            }
          }
        },
      },
      transformations = {
        {
          input = { "test.field" },
          needs = { "test.field" },
          on_write = function() return true end,
        },
      },
    }))
  end)

  it("validates nested transformation needs fields exists (negative)", function()
    assert.falsy(MetaSchema:validate({
      name = "test",
      primary_key = { "test" },
      fields = {
        {
          test = {
            type = "record",
            fields = {
              {
                field = { type = "string" },
              },
            },
          },
        },
      },
      transformations = {
        {
          input = { "test.field" },
          needs = { "test.nonexisting" },
          on_write = function() return true end,
        },
      },
    }))

    assert.falsy(MetaSchema:validate({
      name = "test",
      primary_key = { "test" },
      fields = {
        {
          test = {
            type = "record",
            fields = {
              {
                field = { type = "string" },
              },
            },
          },
        },
      },
      transformations = {
        {
          input = { "test.field" },
          needs = { "nonexisting.field" },
          on_write = function() return true end,
        },
      },
    }))
  end)
end)


describe("metasubschema", function()
  it("rejects a bad schema", function()
    local s = {
      name = "bad",
      fields = {
        { foo = "bar", },
      },
      primary_key = { "foo" },
    }
    local ok, err = MetaSchema.MetaSubSchema:validate(s)
    assert.falsy(ok)
    assert.same({
      fields = {
        "expected a record",
      },
      foo = "'foo' must be a table",
      primary_key = "unknown field"
    }, err)
  end)

  it("fields cannot be empty", function()
    local s = {
      name = "bad",
      fields = {
        {}
      },
    }
    local ok, err = MetaSchema.MetaSubSchema:validate(s)
    assert.falsy(ok)
    assert.match("field entry table is empty", err.fields)
  end)

  it("rejects an invalid entity check", function()
    local s = {
      name = "bad",
      fields = {
        { foo = { type = "number" }, },
      },
      entity_checks = {
        foo = { "bar" },
      }
    }
    local ok, err = MetaSchema.MetaSubSchema:validate(s)
    assert.falsy(ok)
    assert.same({
      entity_checks = "expected an array",
    }, err)
  end)

  it("validates a schema with nested records", function()
    local s = {
      name = "hello",
      fields = {
        { foo = { type = "number" } },
        { f = {
            type = "record",
            fields = {
              { r = {
                  type = "record",
                  fields = {
                    { a = { type = "string" }, },
                    { b = { type = "number" }, } }}}}}}}}
    assert.truthy(MetaSchema.MetaSubSchema:validate(s))
  end)

  it("allows only one entity check per array field", function()
    local s = {
      name = "bad",
      fields = {
        { a = { type = "number" } },
        { b = { type = "number" } },
        { c = { type = "number" } },
        { d = { type = "number" } },
      },
      entity_checks = {
        { only_one_of = { "a", "b" },
          at_least_one_of = { "c", "d" },
        },
      }
    }
    local ok, err = MetaSchema.MetaSubSchema:validate(s)
    assert.falsy(ok)
    assert.match("exactly one of these fields must be non-empty",
                 err.entity_checks[1]["@entity"][1], 1, true)
  end)

  it("accepts a function in an entity check", function()
    local s = {
      name = "bad",
      fields = {
        { a = { type = "number" } },
        { b = { type = "number" } },
      },
      entity_checks = {
        { custom_entity_check = {
            field_sources = { "a" },
            fn = function()
              return true
            end,
          }
        },
      }
    }
    local ok = MetaSchema.MetaSubSchema:validate(s)
    assert.truthy(ok)
  end)

  it("rejects a bad schema checking nested error", function()
    local s = {
      name = "bad",
      fields = {
        {
          foo = {
            type = "array",
            elements = {
              { foo = "bar", },
            }
          }
        }
      },
    }
    local ok, err = MetaSchema.MetaSubSchema:validate(s)
    assert.falsy(ok)
    assert.same({
      fields = {
        {
          elements = {
            "unknown field",
            type = "required field missing",
          }
        }
      },
      foo = "missing type declaration",
    }, err)
  end)

  it("rejects a bad schema matching validators and types", function()
    local s = {
      name = "bad",
      fields = {
        {
          foo = {
            type = "array",
            -- will cause error because `uuid` must be used with `strings`
            elements = { type = "number", uuid = true, },
          }
        }
      },
      primary_key = { "foo" },
    }
    local ret, err = MetaSchema.MetaSubSchema:validate(s)
    assert.falsy(ret)
    assert.same({
      foo = "field of type 'number' cannot have attribute 'uuid'",
      primary_key = "unknown field"
    }, err)
  end)

  it("supports all Schema validators", function()
    local set = MetaSchema.get_supported_validator_set()
    for name, _ in pairs(Schema.validators) do
      assert.truthy(set[name], "'" .. name .. "' is missing from MetaSchema")
    end

    for name, _ in pairs(set) do
      local err = "'" .. name .. "' in MetaSchema is not a declared validator"
      assert.truthy(Schema.validators[name], err)
    end
  end)

  it("allows specifying an endpoint key with endpoint_key", function()
    local s = {
      name = "test",
      fields = {
        { str = { type = "string", unique = true } },
        { num = { type = "number" } },
      },
    }
    assert.truthy(MetaSchema.MetaSubSchema:validate(s))
  end)

  it("supports the unique attribute in base types", function()
    local s = {
      name = "test",
      fields = {
        { str = { type = "string", unique = true } },
        { num = { type = "number", unique = true } },
        { int = { type = "integer", unique = true } },
      },
    }
    assert.truthy(MetaSchema.MetaSubSchema:validate(s))
  end)

  it("rejects the unique attribute in composite types", function()
    local s = {
      name = "test",
      fields = {
        { id  = { type = "string" } },
        { arr = { type = "array", unique = true } },
        { map = { type = "map", unique = true } },
        { rec = { type = "record", unique = true } },
        { set = { type = "set", unique = true } },
      },
    }
    local ok, err = MetaSchema.MetaSubSchema:validate(s)
    assert.falsy(ok)
    assert.match("'array' cannot have attribute 'unique'", err.arr)
    assert.match("'map' cannot have attribute 'unique'", err.map)
    assert.match("'record' cannot have attribute 'unique'", err.rec)
    assert.match("'set' cannot have attribute 'unique'", err.set)
  end)

  it("a schema cannot have a field of type 'any'", function()
    local s = {
      name = "hello",
      primary_key = { "foo" },
      fields = {
        { foo = { type = "any" } } } }
    local ok, err = MetaSchema.MetaSubSchema:validate(s)
    assert.falsy(ok)
    assert.match("expected one of", err.fields[1].type)
  end)

  it("validates a value with 'eq'", function()
    assert.truthy(MetaSchema.MetaSubSchema:validate({
      name = "test",
      fields = {
        { pk = { type = "boolean", default = true, eq = true } },
      },
    }))
  end)

  for plugin, _ in pairs(helpers.test_conf.loaded_plugins) do
    it("validates plugin subschema for " .. plugin, function()
      local schema = require("kong.plugins." .. plugin .. ".schema")
      assert.truthy(MetaSchema.MetaSubSchema:validate(schema))
    end)
  end

  it("validates transformation has transformation function specified (positive)", function()
    assert.truthy(MetaSchema.MetaSubSchema:validate({
      name = "test",
      fields = {
        { test = { type = "string" } },
      },
      transformations = {
        {
          on_write = function() return true end,
        },
      },
    }))

    assert.truthy(MetaSchema.MetaSubSchema:validate({
      name = "test",
      fields = {
        { test = { type = "string" } },
      },
      transformations = {
        {
          input = { "test" },
          on_write = function() return true end,
        },
      },
    }))

    assert.truthy(MetaSchema.MetaSubSchema:validate({
      name = "test",
      fields = {
        { test = { type = "string" } },
      },
      transformations = {
        {
          input = { "test" },
          on_read = function() return true end,
        },
      },
    }))

    assert.truthy(MetaSchema.MetaSubSchema:validate({
      name = "test",
      fields = {
        { test = { type = "string" } },
      },
      transformations = {
        {
          input = { "test" },
          on_read = function() return true end,
          on_write = function() return true end,
        },
      },
    }))
  end)

  it("validates transformation has transformation function specified (negative)", function()
    assert.falsy(MetaSchema.MetaSubSchema:validate({
      name = "test",
      fields = {
        { test = { type = "string" } },
      },
      transformations = {
        {
          input = { "test" },
        },
      },
    }))
  end)

  it("validates transformation input fields exists (positive)", function()
    assert.truthy(MetaSchema.MetaSubSchema:validate({
      name = "test",
      fields = {
        { test = { type = "string" } },
      },
      transformations = {
        {
          input = { "test" },
          on_write = function() return true end,
        },
      },
    }))
  end)

  it("validates transformation input fields exists (negative)", function()
    assert.falsy(MetaSchema.MetaSubSchema:validate({
      name = "test",
      fields = {
        { test = { type = "string" } },
      },
      transformations = {
        {
          input = { "nonexisting" },
          on_write = function() return true end,
        },
      },
    }))
  end)

  it("validates nested transformation input fields exists (positive)", function()
    assert.truthy(MetaSchema.MetaSubSchema:validate({
      name = "test",
      fields = {
        {
          test = {
            type = "record",
            fields = {
              {
                field = { type = "string" }
              },
            }
          }
        },
      },
      transformations = {
        {
          input = { "test.field" },
          on_write = function() return true end,
        },
      },
    }))
  end)

  it("validates nested transformation input fields exists (negative)", function()
    assert.falsy(MetaSchema.MetaSubSchema:validate({
      name = "test",
      fields = {
        {
          test = {
            type = "record",
            fields = {
              {
                field = { type = "string" },
              },
            },
          },
        },
      },
      transformations = {
        {
          input = { "test.nonexisting" },
          on_write = function() return true end,
        },
      },
    }))

    assert.falsy(MetaSchema.MetaSubSchema:validate({
      name = "test",
      fields = {
        {
          test = {
            type = "record",
            fields = {
              {
                field = { type = "string" },
              },
            },
          },
        },
      },
      transformations = {
        {
          input = { "nonexisting.field" },
          on_write = function() return true end,
        },
      },
    }))
  end)

  it("validates transformation needs fields exists (positive)", function()
    assert.truthy(MetaSchema.MetaSubSchema:validate({
      name = "test",
      fields = {
        { test = { type = "string" } },
      },
      transformations = {
        {
          input = { "test" },
          needs = { "test" },
          on_write = function() return true end,
        },
      },
    }))
  end)

  it("validates transformation needs fields exists (negative)", function()
    assert.falsy(MetaSchema.MetaSubSchema:validate({
      name = "test",
      fields = {
        { test = { type = "string" } },
      },
      transformations = {
        {
          input = { "test" },
          needs = { "nonexisting" },
          on_write = function() return true end,
        },
      },
    }))
  end)

  it("validates nested transformation needs fields exists (positive)", function()
    assert.truthy(MetaSchema.MetaSubSchema:validate({
      name = "test",
      fields = {
        {
          test = {
            type = "record",
            fields = {
              {
                field = { type = "string" }
              },
            }
          }
        },
      },
      transformations = {
        {
          input = { "test.field" },
          needs = { "test.field" },
          on_write = function() return true end,
        },
      },
    }))
  end)

  it("validates nested transformation needs fields exists (negative)", function()
    assert.falsy(MetaSchema.MetaSubSchema:validate({
      name = "test",
      fields = {
        {
          test = {
            type = "record",
            fields = {
              {
                field = { type = "string" },
              },
            },
          },
        },
      },
      transformations = {
        {
          input = { "test.field" },
          needs = { "test.nonexisting" },
          on_write = function() return true end,
        },
      },
    }))

    assert.falsy(MetaSchema.MetaSubSchema:validate({
      name = "test",
      fields = {
        {
          test = {
            type = "record",
            fields = {
              {
                field = { type = "string" },
              },
            },
          },
        },
      },
      transformations = {
        {
          input = { "test.field" },
          needs = { "nonexisting.field" },
          on_write = function() return true end,
        },
      },
    }))
  end)

  describe("json fields", function()
    local NS = constants.SCHEMA_NAMESPACES.PROXY_WASM_FILTERS

    it("requires the field to have a json_schema attribute", function()
      local ok, err = MetaSchema:validate({
        name = "test",
        primary_key = { "id" },
        fields = {
          { my_field = { type = "json" } },
          { id = { type = "string" }, },
        },
      })

      assert.falsy(ok)
      assert.is_table(err)
      assert.matches("field of type .json. must declare .json_schema.", err.my_field)

      assert.truthy(MetaSchema:validate({
        name = "test",
        primary_key = { "id" },
        fields = {
          { my_field = {
              type = "json",
              json_schema = { inline = { type = "string" }, },
            }
          },
          { id = { type = "string" }, },
        },
      }))
    end)

    it("requires at least one of `inline` or `namespace`/`parent_subschema_key`", function()
      local ok, err = MetaSchema:validate({
        name = "test",
        primary_key = { "id" },
        fields = {
          { my_field = {
              type = "json",
              json_schema = { },
            }
          },
          { id = { type = "string" }, },
        },
      })

      assert.falsy(ok)
      assert.is_table(err)
      assert.is_table(err.fields)
      assert.same({
          {
            json_schema = {
              ["@entity"] = {
                "at least one of these fields must be non-empty: 'inline', 'namespace', 'parent_subschema_key'"
              }
            }
          }
        }, err.fields)
    end)

    it("requires that inline schemas are valid", function()
      local ok, err = MetaSchema:validate({
        name = "test",
        primary_key = { "id" },
        fields = {
          { my_field = {
              type = "json",
              json_schema = {
                inline = {
                  type = "not a valid json schema type",
                },
              },
            }
          },
          { id = { type = "string" }, },
        },
      })

      assert.falsy(ok)
      assert.is_table(err)
      assert.is_table(err.fields)
      assert.same({
        {
          json_schema = {
            inline = "property type validation failed: object needs one of the following rectifications: 1) matches none of the enum values; 2) wrong type: expected array, got string"
          }
        }
      }, err.fields)

      assert.truthy(MetaSchema:validate({
        name = "test",
        primary_key = { "id" },
        fields = {
          { my_field = {
              type = "json",
              json_schema = {
                inline = {
                  type = "string",
                },
              },
            }
          },
          { id = { type = "string" }, },
        },
      }))
    end)

    it("only allows currently-supported versions of JSON schema", function()
      local invalid = {
        "http://json-schema.org/draft-07/schema#",
        "https://json-schema.org/draft/2019-09/schema",
        "https://json-schema.org/draft/2020-12/schema",
      }

      local inline_schema = {
        type = "string",
      }

      local schema = {
        name = "test",
        primary_key = { "id" },
        fields = {
          { my_field = {
              type = "json",
              json_schema = {
                inline = inline_schema,
              }
            }
          },
          { id = { type = "string" }, },
        }
      }

      for _, version in ipairs(invalid) do
        inline_schema["$schema"] = version
        local ok, err = MetaSchema:validate(schema)
        assert.is_nil(ok)
        assert.is_table(err)
        assert.is_table(err.fields)
        assert.is_table(err.fields[1])
        assert.is_table(err.fields[1].json_schema)
        assert.matches('unsupported document $schema',
                       err.fields[1].json_schema.inline, nil, true)
      end

      -- with fragment
      inline_schema["$schema"] = "http://json-schema.org/draft-04/schema#"
      assert.truthy(MetaSchema:validate(schema))

      -- sans fragment
      inline_schema["$schema"] = "http://json-schema.org/draft-04/schema"
      assert.truthy(MetaSchema:validate(schema))

      -- $schema is ultimately optional
      inline_schema["$schema"] = nil
      assert.truthy(MetaSchema:validate(schema))
    end)

    it("mutually requires `namespace` and `parent_subschema_key`", function()
      local ok, err = MetaSchema:validate({
        name = "test",
        primary_key = { "id" },
        fields = {
          { my_field = {
              type = "json",
              json_schema = {
                namespace = NS,
              },
            }
          },
          { id = { type = "string" }, },
        },
      })

      assert.falsy(ok)
      assert.is_table(err)
      assert.is_table(err.fields)
      assert.same({
          {
            json_schema = {
              ["@entity"] = {
                "all or none of these fields must be set: 'namespace', 'parent_subschema_key'"
              }
            }
          }
        }, err.fields)

      ok, err = MetaSchema:validate({
        name = "test",
        primary_key = { "id" },
        fields = {
          { my_field = {
              type = "json",
              json_schema = {
                parent_subschema_key = "id",
              },
            }
          },
          { id = { type = "string" }, },
        },
      })

      assert.falsy(ok)
      assert.is_table(err)
      assert.is_table(err.fields)
      assert.same({
          {
            json_schema = {
              ["@entity"] = {
                "all or none of these fields must be set: 'namespace', 'parent_subschema_key'"
              }
            }
          }
        }, err.fields)
    end)

    it("requires that `parent_subschema_key` is a string field of the parent schema", function()
      local ok, err = MetaSchema:validate({
        name = "test",
        primary_key = { "id" },
        fields = {
          { my_field = {
              type = "json",
              json_schema = {
                namespace = NS,
                parent_subschema_key = "my_nonexistent_field",
              },
            }
          },
          { id = { type = "string" }, },
        },
      })

      assert.falsy(ok)
      assert.same({
          my_field = {
            json_schema = {
              parent_subschema_key = "value must be a field name of the parent schema"
            }
          }
        }, err)

      ok, err = MetaSchema:validate({
        name = "test",
        primary_key = { "id" },
        fields = {
          { my_field = {
              type = "json",
              json_schema = {
                namespace = NS,
                parent_subschema_key = "my_non_string_field",
              },
            }
          },
          { id = { type = "string" }, },
          { my_non_string_field = { type = "number" } },
        },
      })

      assert.falsy(ok)
      assert.same({
          my_field = {
            json_schema = {
              parent_subschema_key = "value must be a string field of the parent schema",
            }
          }
        }, err)

      assert.truthy(MetaSchema:validate({
        name = "test",
        primary_key = { "id" },
        fields = {
          { my_field = {
              type = "json",
              json_schema = {
                namespace = NS,
                parent_subschema_key = "my_string_field",
              },
            }
          },
          { id = { type = "string" }, },
          { my_string_field = { type = "string" }, },
        },
      }))

    end)

  end)
end)
