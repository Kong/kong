-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"


for _, strategy in helpers.each_strategy() do
  local bp, db

  describe("cascade delete workspace entities [#" .. strategy .. "]", function()
    setup(function()
      bp, db = helpers.get_db_utils(strategy)
    end)

    it(":delete", function()
      db:truncate("consumers")
      db:truncate("workspaces")

      local w1 = assert(bp.workspaces:insert({ name = "w1" }))
      local c1 = assert(bp.consumers:insert_ws({ username = "c1" }, w1))
      assert(bp.basicauth_credentials:insert_ws({
        username = "gruce",
        password = "ovo",
        consumer = { id = c1.id },
      }, w1))

      db.consumers:delete({ id = c1.id }, { workspace = w1.id })
    end)

    it(":delete_by", function()
      db:truncate("consumers")
      db:truncate("workspaces")

      local w1 = assert(bp.workspaces:insert({ name = "w1" }))
      local c1 = assert(bp.consumers:insert_ws({ username = "c1" }, w1))
      assert(bp.basicauth_credentials:insert_ws({
        username = "gruce",
        password = "ovo",
        consumer = { id = c1.id },
      }, w1))

      db.consumers:delete_by_username(c1.username, { workspace = w1.id })
    end)
  end)
end
