-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers     = require "spec.helpers"
local api_helpers = require "kong.enterprise_edition.api_helpers"

for _, strategy in helpers.each_strategy() do
describe("kong.enterprise_edition.api_helpers", function()
  describe(".resolve_entity_type", function()
    local bp, db

    setup(function()
      bp, db = helpers.get_db_utils(strategy)
    end)

    it("resolves new and old daos entity types", function()
      local entities = {
        consumers = bp.consumers:insert(),
        plugins  = bp.plugins:insert({name = "dummy"}),
        services = bp.services:insert(),
        routes = bp.routes:insert({methods = {"GET"}, hosts = {"example.com"}}),
      }
      for entity_type, entity in pairs(entities) do
        local typ, _, err = api_helpers.resolve_entity_type(db,
          entity.id)
        assert.equal(typ, entity_type)
        assert.is_nil(err)
      end
    end)
  end)
end)
end
