return {
  {
    name = "2015-08-03-132400_init_basicauth",
    up = [[
      CREATE TABLE IF NOT EXISTS basicauth_credentials(
        id uuid,
        consumer_id uuid REFERENCES consumers (id) ON DELETE CASCADE,
        username text,
        password text,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc'),
        PRIMARY KEY (id)
      );

      DO $$
      BEGIN
        IF (SELECT to_regclass('basicauth_username_idx')) IS NULL THEN
          CREATE INDEX basicauth_username_idx ON basicauth_credentials(username);
        END IF;
        IF (SELECT to_regclass('basicauth_consumer_id_idx')) IS NULL THEN
          CREATE INDEX basicauth_consumer_id_idx ON basicauth_credentials(consumer_id);
        END IF;
      END$$;
    ]],
    down =  [[
      DROP TABLE basicauth_credentials;
    ]]
  },
  {
    name = "2017-01-25-180400_unique_username",
    up = [[
      ALTER TABLE basicauth_credentials ADD CONSTRAINT basicauth_credentials_username_key UNIQUE(username);
    ]],
    down = [[
      ALTER TABLE basicauth_credentials DROP CONSTRAINT basicauth_credentials_username_key;
    ]]
  },
  {
    name = "2017-07-23-100000_rbac_basicauth_resources",
    up = function(_, _, dao)
      local rbac = require "kong.core.rbac"
      local bxor = require("bit").bxor

      local resource, err = rbac.register_resource("basic-auth", dao)
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
