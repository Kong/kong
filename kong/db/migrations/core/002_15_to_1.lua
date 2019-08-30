return {
  postgres = {
    up = [[
    ]],

    teardown = function(connector)
      assert(connector:query([[
        DO $$
        BEGIN
          DELETE FROM plugins WHERE name = 'galileo';
        EXCEPTION WHEN UNDEFINED_COLUMN OR UNDEFINED_TABLE THEN
          -- Do nothing, accept existing state
        END$$;
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
