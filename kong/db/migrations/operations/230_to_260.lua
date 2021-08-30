-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

-- Helper module for 230_to_260 migration operations.
--
-- Operations are versioned and specific to a migration so they remain
-- fixed in time and are not modified for use in future migrations.
--
-- If you want to reuse these operations in a future migration,
-- copy the functions over to a new versioned module.

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
  cassandra_copy_usernames_to_lower = cassandra_copy_usernames_to_lower
}