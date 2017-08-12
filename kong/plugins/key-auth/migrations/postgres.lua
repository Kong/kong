return {
  {
    name = "2015-07-31-172400_init_keyauth",
    up = [[
      CREATE TABLE IF NOT EXISTS keyauth_credentials(
        id uuid,
        consumer_id uuid REFERENCES consumers (id) ON DELETE CASCADE,
        key text UNIQUE,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc'),
        PRIMARY KEY (id)
      );

      DO $$
      BEGIN
        IF (SELECT to_regclass('keyauth_key_idx')) IS NULL THEN
          CREATE INDEX keyauth_key_idx ON keyauth_credentials(key);
        END IF;
        IF (SELECT to_regclass('keyauth_consumer_idx')) IS NULL THEN
          CREATE INDEX keyauth_consumer_idx ON keyauth_credentials(consumer_id);
        END IF;
      END$$;
    ]],
    down = [[
      DROP TABLE keyauth_credentials;
    ]]
  },
  {
    name = "2017-07-23-100000_rbac_keyauth_resources",
    up = function(_, _, dao)
      local rbac = require "kong.core.rbac"
      local bxor = require("bit").bxor

      local resource, err = rbac.register_resource("key-auth", dao)
      if not resource then
        return err
      end

      for _, p in ipairs({ "read-only", "full-access" }) do
        local perm, err = dao.rbac_perms:find_all({
          name = p,
        })
        if err then
          return err
        end
        perm = perm[1]
        perm.resources = bxor(perm.resources, 2 ^ (resource.bit_pos - 1))
        local ok, err = dao.rbac_perms:update(perm, { id = perm.id })
        if not ok then
          return err
        end
      end
    end,
  },
}
