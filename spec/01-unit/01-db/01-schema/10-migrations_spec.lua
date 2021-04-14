-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

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
