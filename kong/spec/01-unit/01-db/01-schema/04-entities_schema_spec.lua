local Entity = require "kong.db.schema.entity"


describe("entity schema", function()
  -- the entity subschema is a subclass for DAO (database) entities

  it("rejects fields with 'function' type", function()
    local s = {
      name = "invalid",
      fields = {
        { f = { type = "function" } },
      },
    }
    local ok, err = Entity.new(s)
    assert.is_nil(ok)
    assert.equal("f: Entities cannot have function types.", err)
  end)

  it("rejects fields with 'nilable' types", function()
    local s = {
      name = "invalid",
      fields = {
        { nilable = { type = "string", nilable = true } },
      },
    }
    local ok, err = Entity.new(s)
    assert.is_nil(ok)
    assert.equal("nilable: Entities cannot have nilable types.", err)
  end)

  it("rejects fields with non-string 'map' keys", function()
    local s = {
      name = "invalid",
      fields = {
        { a_map = {
            type = "map",
            keys = { type = "number" },
            values = { type = "string" },
          },
        },
      },
    }
    local ok, err = Entity.new(s)
    assert.is_nil(ok)
    assert.equal("a_map: Entities map keys must be strings.", err)
  end)
end)
