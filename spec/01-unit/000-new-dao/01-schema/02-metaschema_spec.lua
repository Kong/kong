local Schema = require "kong.db.schema"
local MetaSchema = require "kong.db.schema.metaschema"


Schema.new(MetaSchema)


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
