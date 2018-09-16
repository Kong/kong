return {
  postgres = {
    up = [[
      DO $$
      BEGIN
        ALTER TABLE oauth2_credentials
        ADD COLUMN redirect_uris TEXT[];
      EXCEPTION WHEN duplicate_column THEN
        -- Do nothing, accept existing state
      END$$;

      DO $$
        BEGIN
        UPDATE oauth2_credentials
        SET redirect_uris = TRANSLATE(redirect_uri, '[]','{}')::TEXT[];
        EXCEPTION WHEN undefined_column THEN
        -- Do nothing, accept existing state
      END$$;

      DO $$
      BEGIN
        ALTER TABLE oauth2_authorization_codes
        ADD COLUMN ttl timestamp with time zone;
      EXCEPTION WHEN duplicate_column THEN
        -- Do nothing, accept existing state
      END$$;

      UPDATE oauth2_authorization_codes
        SET ttl = created_at + interval '300 seconds';

      DO $$
      BEGIN
        ALTER TABLE oauth2_tokens
        ADD COLUMN ttl timestamp with time zone;
      EXCEPTION WHEN duplicate_column THEN
        -- Do nothing, accept existing state
      END$$;

      UPDATE oauth2_tokens
        SET ttl = created_at + (expires_in || ' second')::interval;
    ]],

    teardown = function(connector)
      assert(connector:query [[
        DO $$
        BEGIN
          ALTER TABLE oauth2_credentials
          DROP COLUMN redirect_uri;
        EXCEPTION WHEN undefined_column THEN
          -- Do nothing, accept existing state
        END$$;
      ]])
    end,
  },

  cassandra = {
    up = [[
      ALTER TABLE oauth2_credentials ADD redirect_uris set<text>;
    ]],

    teardown = function(connector)
      local cjson = require "cjson"
      local coordinator = assert(connector:connect_migrations())

      for rows, err in coordinator:iterate([[
        SELECT id, redirect_uri FROM oauth2_credentials]]) do
        if err then
          return nil, err
        end

        for _, row in ipairs(rows) do
          local uris = cjson.decode(row.redirect_uri)
          local buffer = {}

          for i, uri in ipairs(uris) do
            buffer[i] = "'" .. uri .. "'"
          end

          local q = string.format([[
                      UPDATE oauth2_credentials
                      SET redirect_uris = {%s} WHERE id = %s
                    ]], table.concat(buffer, ","), row.id)

          assert(connector:query(q))
        end
      end

      assert(connector:query([[
        ALTER TABLE oauth2_credentials DROP redirect_uri
      ]]))
    end,
  },
}
