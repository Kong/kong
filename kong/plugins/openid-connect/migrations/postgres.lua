local is_ee, rbac = pcall(require, "kong.core.rbac")
local migrations = {
  {
    name = "2017-06-01-180000_init_oic",
    up = [[
      CREATE TABLE IF NOT EXISTS oic_issuers (
        id            uuid,
        issuer        text UNIQUE,
        configuration text,
        keys          text,
        created_at    timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc'),
        PRIMARY KEY (id)
      );

      DO $$
      BEGIN
        IF (SELECT to_regclass('oic_issuers_idx')) IS NULL THEN
          CREATE INDEX oic_issuers_idx ON oic_issuers (issuer);
        END IF;
      END$$;

      CREATE TABLE IF NOT EXISTS oic_signout (
        id            uuid,
        jti           text,
        iss           text,
        sid           text,
        sub           text,
        aud           text,
        created_at    timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc'),
        PRIMARY KEY (id)
      );

      DO $$
      BEGIN
        IF (SELECT to_regclass('oic_signout_iss_idx')) IS NULL THEN
          CREATE INDEX oic_signout_iss_idx ON oic_signout (iss);
        END IF;
      END$$;

      DO $$
      BEGIN
        IF (SELECT to_regclass('oic_signout_sid_idx')) IS NULL THEN
          CREATE INDEX oic_signout_sid_idx ON oic_signout (sid);
        END IF;
      END$$;

      DO $$
      BEGIN
        IF (SELECT to_regclass('oic_signout_sub_idx')) IS NULL THEN
          CREATE INDEX oic_signout_sub_idx ON oic_signout (sub);
        END IF;
      END$$;

      DO $$
      BEGIN
        IF (SELECT to_regclass('oic_signout_jti_idx')) IS NULL THEN
          CREATE INDEX oic_signout_jti_idx ON oic_signout (jti);
        END IF;
      END$$;

      CREATE TABLE IF NOT EXISTS oic_session (
        id            uuid,
        sid           text UNIQUE,
        expires       int,
        data          text,
        created_at    timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc'),
        PRIMARY KEY (id)
      );

      DO $$
      BEGIN
        IF (SELECT to_regclass('oic_session_sid_idx')) IS NULL THEN
          CREATE INDEX oic_session_sid_idx ON oic_session (sid);
        END IF;
      END$$;

      DO $$
      BEGIN
        IF (SELECT to_regclass('oic_session_exp_idx')) IS NULL THEN
          CREATE INDEX oic_session_exp_idx ON oic_session (expires);
        END IF;
      END$$;

      CREATE TABLE IF NOT EXISTS oic_revoked (
        id            uuid,
        hash          text,
        expires       int,
        created_at    timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc'),
        PRIMARY KEY (id)
      );

      DO $$
      BEGIN
        IF (SELECT to_regclass('oic_session_hash_idx')) IS NULL THEN
          CREATE INDEX oic_session_hash_idx ON oic_revoked (hash);
        END IF;
      END$$;

      DO $$
      BEGIN
        IF (SELECT to_regclass('oic_session_exp_idx')) IS NULL THEN
          CREATE INDEX oic_session_exp_idx ON oic_revoked (expires);
        END IF;
      END$$;
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
      ALTER TABLE oic_issuers ADD COLUMN secret text;
    ]],
    down = [[
      ALTER TABLE oic_issuers ADD COLUMN secret text;
    ]],
  },
}


if is_ee then
  migrations[#migrations+1] = {
    name = "2017-08-26-150000_rbac_oic_resources",
    up = function(_, _, dao)
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
  }
end


return migrations
