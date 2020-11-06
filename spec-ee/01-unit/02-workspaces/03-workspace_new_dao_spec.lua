-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

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
