-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local function cassandra_copy_usernames_to_lower(coordinator, table_name)
  local cassandra = require "cassandra"
  for rows, err in coordinator:iterate("SELECT id, username FROM " .. table_name) do
    if err then
      return nil, err
    end

    for _, row in ipairs(rows) do
      if type(row.username) == 'string' then
        local _, err = coordinator:execute("UPDATE " .. table_name .. " SET username_lower = ? WHERE id = ?", {
          cassandra.text(row.username:lower()),
          cassandra.uuid(row.id),
        })
        if err then
          return nil, err
        end
      end
    end
  end

  return true
end

return {
  postgres = {
    up = [[
      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "consumers" ADD "username_lower" TEXT;
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END;
      $$;

      UPDATE consumers SET username_lower=LOWER(username);

      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "admins" ADD "username_lower" TEXT;
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END;
      $$;

      UPDATE admins SET username_lower=LOWER(username);
    ]]
  },
  cassandra = {
    up = [[
      ALTER TABLE consumers ADD username_lower TEXT;
      CREATE INDEX IF NOT EXISTS consumers_username_lower_idx ON consumers(username_lower);

      ALTER TABLE admins ADD username_lower TEXT;
      CREATE INDEX IF NOT EXISTS admins_username_lower_idx ON admins(username_lower);
    ]],
    teardown = function(connector)
      local coordinator = assert(connector:get_stored_connection())

      local success, err
      for _, table_name in ipairs({ "consumers", "admins "}) do
        success, err = cassandra_copy_usernames_to_lower(coordinator, table_name)

        if err then
          return nil, err
        end
      end

      return success
    end,
  }
}
