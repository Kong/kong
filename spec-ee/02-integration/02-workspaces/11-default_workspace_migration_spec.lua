-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"

for _, strategy in helpers.each_strategy() do
  describe("default workspace after migrations [#" .. strategy .. "]", function()
    it("is contains the correct defaults", function()
      local _, db
      _, db = helpers.get_db_utils(strategy, { "workspaces" })
      local default_ws = assert(db.workspaces:select_by_name("default"))
      assert.equal("default", default_ws.name)
      assert.same({}, default_ws.meta)
      assert.is_not_nil(default_ws.created_at)
      assert.equal(false , default_ws.config.portal)
    end)
  end)
end
