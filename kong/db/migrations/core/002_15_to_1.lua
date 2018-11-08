return {
  postgres = {
    up = [[
    ]],

    teardown = function(connector)
      assert(connector:query([[
        DELETE FROM "plugins" WHERE name = "galileo";
      ]]))
    end,
  },

  cassandra = {
    up = [[
    ]],

    teardown = function(connector)
      local cassandra = require "cassandra"
      local coordinator = assert(connector:connect_migrations())

      for rows, err in coordinator:iterate([[
        SELECT id FROM plugins WHERE name = 'galileo';
      ]]) do
        if err then
          return nil, err
        end

        for i = 1, #rows do
          assert(connector:query("DELETE FROM plugins WHERE id = ?", {
            cassandra.uuid(rows[i].id),
          }))
        end
      end
    end,
  },
}
