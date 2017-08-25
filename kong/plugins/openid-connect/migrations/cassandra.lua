return {
  {
    name = "2017-06-01-180000_init_oic",
    up = [[
      CREATE TABLE IF NOT EXISTS oic_issuers (
        id            uuid,
        issuer        text,
        configuration text,
        keys          text,
        created_at    timestamp,
        PRIMARY KEY (id)
      );

      CREATE INDEX IF NOT EXISTS ON oic_issuers (issuer);

      CREATE TABLE IF NOT EXISTS oic_signout (
        id            uuid,
        jti           text,
        iss           text,
        sid           text,
        sub           text,
        aud           text,
        created_at    timestamp,
        PRIMARY KEY (id)
      );

      CREATE INDEX IF NOT EXISTS ON oic_signout (iss);
      CREATE INDEX IF NOT EXISTS ON oic_signout (sid);
      CREATE INDEX IF NOT EXISTS ON oic_signout (sub);
      CREATE INDEX IF NOT EXISTS ON oic_signout (jti);

      CREATE TABLE IF NOT EXISTS oic_session (
        id            uuid,
        sid           text,
        expires       int,
        data          text,
        created_at    timestamp,
        PRIMARY KEY (id)
      );

      CREATE INDEX IF NOT EXISTS ON oic_session (sid);
      CREATE INDEX IF NOT EXISTS ON oic_session (expires);

      CREATE TABLE IF NOT EXISTS oic_revoked (
        id            uuid,
        hash          text,
        expires       int,
        created_at    timestamp,
        PRIMARY KEY (id)
      );

      CREATE INDEX IF NOT EXISTS ON oic_revoked (hash);
      CREATE INDEX IF NOT EXISTS ON oic_revoked (expires);
    ]],
    down = [[
      DROP TABLE oic_issuers;
      DROP TABLE oic_signout;
      DROP TABLE oic_session;
      DROP TABLE oic_revoked;
    ]]
  },
  {
    name = "2017-08-09-160000-add-secret-used-for-sessions",
    up = [[
      ALTER TABLE oic_issuers ADD secret text;
    ]],
    down = [[
      ALTER TABLE oic_issuers DROP secret;
    ]]
  },
  {
    name = "2017-08-26-150000_rbac_oic_resources",
    up = function(_, _, dao)
      local rbac = require "kong.core.rbac"
      local bxor = require("bit").bxor

      local resource, err = rbac.register_resource("openid-connect", dao)
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
