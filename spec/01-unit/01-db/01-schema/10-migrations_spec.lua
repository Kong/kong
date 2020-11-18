local Migrations = require "kong.db.schema.others.migrations"
local Schema = require "kong.db.schema"
local helpers = require "spec.helpers"


local MigrationsSchema = Schema.new(Migrations)


describe("migrations schema", function()

  it("validates 'name' field", function()
    local ok, errs = MigrationsSchema:validate {
      postgres = { up = "" },
      cassandra = { up = "" },
    }
    assert.is_nil(ok)
    assert.equal("required field missing", errs["name"])
  end)

  for _, strategy in helpers.each_strategy({"postgres", "cassandra"}) do

    it("requires at least one field of pg.up, pg.teardown, c.up, c.up_f, c.teardown", function()
      local t = {}

      local ok, errs = MigrationsSchema:validate(t)
      assert.is_nil(ok)
      assert.same({"at least one of these fields must be non-empty: " ..
        "'postgres.up', 'postgres.teardown', 'cassandra.up', 'cassandra.up_f', " ..
        "'cassandra.teardown'" },
        errs["@entity"])
    end)

    it("validates '<strategy>.up' property", function()
      local not_a_string = 1
      local t = {
        [strategy] = {
          up = not_a_string
        }
      }

      local ok, errs = MigrationsSchema:validate(t)
      assert.is_nil(ok)
      assert.equal("expected a string", errs[strategy]["up"])
    end)

    if strategy == "cassandra" then
      it("validates '<strategy>.up_f' property in cassandra", function()
        local t = {
          cassandra = { up_f = "this is not a function" },
        }

        local ok, errs = MigrationsSchema:validate(t)
        assert.is_nil(ok)
        assert.equal("expected a function", errs[strategy]["up_f"])
      end)
    end

    it("validates '<strategy>.teardown' property", function()
      local t = {
        [strategy] = {
          teardown = "not a function"
        }
      }

      local ok, errs = MigrationsSchema:validate(t)
      assert.is_nil(ok)
      assert.equal("expected a function", errs[strategy]["teardown"])
    end)

  end
end)
