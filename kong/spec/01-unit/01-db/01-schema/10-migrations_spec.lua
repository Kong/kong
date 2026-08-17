local Migrations = require "kong.db.schema.others.migrations"
local Schema = require "kong.db.schema"


local MigrationsSchema = Schema.new(Migrations)


describe("migrations schema", function()

  it("validates 'name' field", function()
    local ok, errs = MigrationsSchema:validate {
      postgres = { up = "" },
    }
    assert.is_nil(ok)
    assert.equal("required field missing", errs["name"])
  end)

  it("requires at least one field of pg.up, pg.up_f, pg.teardown", function()
    local t = {}

    local ok, errs = MigrationsSchema:validate(t)
    assert.is_nil(ok)
    assert.same({"at least one of these fields must be non-empty: " ..
      "'postgres.up', 'postgres.up_f', 'postgres.teardown'" },
      errs["@entity"])
  end)

  it("validates 'postgres.up' property", function()
    local not_a_string = 1
    local t = {
      ["postgres"] = {
        up = not_a_string
      }
    }

    local ok, errs = MigrationsSchema:validate(t)
    assert.is_nil(ok)
    assert.equal("expected a string", errs["postgres"]["up"])
  end)

  it("validates 'postgres.up_f' property", function()
    local t = {
      ["postgres"] = {
        up_f = "this is not a function"
      }
    }

    local ok, errs = MigrationsSchema:validate(t)
    assert.is_nil(ok)
    assert.equal("expected a function", errs["postgres"]["up_f"])
  end)

  it("validates 'postgres.teardown' property", function()
    local t = {
      ["postgres"] = {
        teardown = "not a function"
      }
    }

    local ok, errs = MigrationsSchema:validate(t)
    assert.is_nil(ok)
    assert.equal("expected a function", errs["postgres"]["teardown"])
  end)

end)
