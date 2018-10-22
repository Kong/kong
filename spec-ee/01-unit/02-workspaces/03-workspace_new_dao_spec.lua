local Schema = require "kong.db.schema"
local MetaSchema = require "kong.db.schema.metaschema"


Schema.new(MetaSchema)


describe("metaschema", function()
  it("support workspaceable attribute", function()
    local s = {
      name = "test",
      workspaceable = true,
      fields = {
        { str = { type = "string", unique = true } },
      },
      primary_key = { "str" },
    }
    assert.truthy(MetaSchema:validate(s))

    s = {
      name = "test",
      workspaceable = false,
      fields = {
        { str = { type = "string", unique = true } },
      },
      primary_key = { "str" },
    }
    assert.truthy(MetaSchema:validate(s))

    s = {
      name = "test",
      workspaceable = ngx.null,
      fields = {
        { str = { type = "string", unique = true } },
      },
      primary_key = { "str" },
    }
    assert.truthy(MetaSchema:validate(s))
  end)

  it("workspaceable attribute can be null", function()
    local s = {
      name = "test",
      workspaceable = ngx.null,
      fields = {
        { str = { type = "string", unique = true } },
      },
      primary_key = { "str" },
    }
    assert.truthy(MetaSchema:validate(s))

    local s = {
      name = "test",
      workspaceable = nil,
      fields = {
        { str = { type = "string", unique = true } },
      },
      primary_key = { "str" },
    }
    assert.truthy(MetaSchema:validate(s))
  end)
end)
