return {
  {
    name = "2015-09-16-132400_init_hmacauth",
    up = [[
       CREATE TABLE IF NOT EXISTS hmacauth_credentials(
        id uuid,
        consumer_id uuid,
        username text,
        secret text,
        created_at timestamp,
        PRIMARY KEY (id)
      );

      CREATE INDEX IF NOT EXISTS ON hmacauth_credentials(username);
      CREATE INDEX IF NOT EXISTS hmacauth_consumer_id ON hmacauth_credentials(consumer_id);
    ]],
    down = [[
      DROP TABLE hmacauth_credentials;
    ]]
  },
  {
    name = "2017-06-21-132400_init_hmacauth",
    up = function(_, _, dao)
      local rows, err = dao.plugins:find_all { name = "hmac-auth" }
      if err then
        return err
      end

      for _, row in ipairs(rows) do
        row.config.validate_request_body = false
        row.config.enforce_headers = {}
        row.config.algorithms = { "hmac-sha1" }
        local _, err = dao.plugins:update(row, row)
        if err then
          return err
        end
      end
    end,
    down = function()
    end
  },
  {
    name = "2017-07-23-100000_rbac_hmacauth_resources",
    up = function(_, _, dao)
      local rbac = require "kong.core.rbac"
      local bxor = require("bit").bxor

      local resource, err = rbac.register_resource("hmac-auth", dao)
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
