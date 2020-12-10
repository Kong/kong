-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS "foos" (
        "color" TEXT PRIMARY KEY
      );

      INSERT INTO foos (color) values ('red');
    ]],
  },

  cassandra = {
    up = [[
      CREATE TABLE IF NOT EXISTS foos (
        color text PRIMARY KEY
      );

      INSERT INTO foos(color) values('red');
    ]],
    up_f = function(connector)
      local coordinator = assert(connector:get_stored_connection())
      local _, err = coordinator:execute([[
        INSERT INTO foos(color) values('green');
      ]])

      if err then
        return nil, err
      end

      return true
    end,
  },
}
