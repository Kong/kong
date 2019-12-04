local fmt = string.format

return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS keyring_meta (
        id text PRIMARY KEY,
        state text not null,
        created_at timestamp with time zone not null
      );
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

      CREATE TABLE IF NOT EXISTS "dbus" (
        "id"           UUID                         UNIQUE,
        "created_at"   TIMESTAMP WITHOUT TIME ZONE  DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        "source"       TEXT NOT NULL,
        "event"        TEXT,
        "handler"      TEXT NOT NULL,
        "config"       JSON                         NOT NULL
      );
    ]],

    teardown = function(connector)

    end,
  },

  cassandra = {
    up = [[
      CREATE TABLE IF NOT EXISTS keyring_meta (
        id            text PRIMARY KEY,
        state         TEXT,
        created_at    timestamp
      );
      CREATE TABLE IF NOT EXISTS keyring_meta_active (
        active text PRIMARY KEY,
        id text
      );
      ALTER TABLE admins ADD rbac_token_enabled boolean;
    ]],

    teardown = function(connector)
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
  }
}
