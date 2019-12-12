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

    it("requires all strategies to be specified", function()
      local t = {
        postgres = { up = "" },
        cassandra = { up = "" },
      }

      t[strategy] = nil

      local ok, errs = MigrationsSchema:validate(t)
      assert.is_nil(ok)
      assert.equal("required field missing", errs[strategy])
    end)

    it("validates '<strategy>.up' property", function()
      local t = {
        postgres = { up = "" },
        cassandra = { up = "" },
      }

      t[strategy].up = nil

      local ok, errs = MigrationsSchema:validate(t)
      assert.is_nil(ok)
      assert.equal("required field missing", errs[strategy]["up"])
    end)

    it("allows '<strategy>.up' property to be a function", function()
      local t = {
        name = "foo",
        postgres = { up = function() end },
        cassandra = { up = function() end },
      }

      local ok, errs = MigrationsSchema:validate(t)
      assert.is_truthy(ok)
      assert.is_nil(errs)
    end)

    it("validates '<strategy>.teardown' property", function()
      local t = {
        postgres = { up = "" },
        cassandra = { up = "" },
      }

      t[strategy].teardown = ""

      local ok, errs = MigrationsSchema:validate(t)
      assert.is_nil(ok)
      assert.equal("expected a function", errs[strategy]["teardown"])
    end)

  end
end)
