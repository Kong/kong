local fmt = string.format

return {
  postgres = {
    up = [[
      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY admins ADD rbac_token_enabled BOOLEAN;
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END;
      $$;

      UPDATE admins
      SET rbac_token_enabled = rbac_users.enabled
      FROM rbac_users
      WHERE admins.rbac_user_id = rbac_users.id;

      ALTER TABLE admins
      ALTER COLUMN rbac_token_enabled SET NOT NULL;
    ]],
    teardown = function(connector)
    end
  },

  cassandra = {
    up = [[
      ALTER TABLE admins ADD rbac_token_enabled boolean;
    ]],
    teardown = function(connector, helpers)
      local coordinator = connector:connect_migrations()

      for rows, err in coordinator:iterate("SELECT rbac_user_id, id FROM admins") do
        if err then
          return nil, err
        end

        for _, admin in ipairs(rows) do
          local rbac_users, err = connector:query(
            fmt("SELECT enabled FROM rbac_users WHERE id = %s", admin.rbac_user_id)
          )
          if err then
            return nil, err
          end

          _, err = connector:query(
            fmt("UPDATE admins SET rbac_token_enabled = %s WHERE id = %s",
                rbac_users[1].enabled, admin.id)
          )
          if err then
            return nil, err
          end
        end
      end
    end
  },
}
