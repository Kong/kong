local Schema = require "kong.db.schema"
local MetaSchema = require "kong.db.schema.metaschema"


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

  it("ttl can only be enabled on entities that have a 'created_at' timestamp field", function()
    local s = {
      name = "test",
      ttl = "true",
      fields = {
        { str = { type = "string", unique = true } },
      },
      primary_key = { "str" },
    }
    local ok, err = MetaSchema:validate(s)
    assert.falsy(ok)
    assert.match("ttl can only be enabled on entities that have a 'created_at' timestamp field", err.ttl)
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
end)
