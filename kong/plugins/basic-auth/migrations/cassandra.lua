return {
  {
    name = "2015-08-03-132400_init_basicauth",
    up = [[
       CREATE TABLE IF NOT EXISTS basicauth_credentials(
        id uuid,
        consumer_id uuid,
        username text,
        password text,
        created_at timestamp,
        PRIMARY KEY (id)
      );

      CREATE INDEX IF NOT EXISTS ON basicauth_credentials(username);
      CREATE INDEX IF NOT EXISTS basicauth_consumer_id ON basicauth_credentials(consumer_id);
    ]],
    down = [[
      DROP TABLE basicauth_credentials;
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
