return {
  postgres = {
    up = [[
      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "oauth2_credentials" ADD "redirect_uris" TEXT[];
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;

      DO $$
      BEGIN
        UPDATE "oauth2_credentials"
           SET "redirect_uris" = TRANSLATE("redirect_uri", '[]', '{}')::TEXT[];
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;


      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "oauth2_authorization_codes" ADD "ttl" TIMESTAMP WITH TIME ZONE;
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;

      UPDATE "oauth2_authorization_codes"
         SET "ttl" = "created_at" + INTERVAL '300 seconds';


      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "oauth2_tokens" ADD "ttl" TIMESTAMP WITH TIME ZONE;
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;

      UPDATE "oauth2_tokens"
         SET "ttl" = "created_at" + (COALESCE("expires_in", 0)::TEXT || ' seconds')::INTERVAL;


      ALTER TABLE IF EXISTS ONLY "oauth2_credentials"
        ALTER "created_at" TYPE TIMESTAMP WITH TIME ZONE USING "created_at" AT TIME ZONE 'UTC',
        ALTER "created_at" SET DEFAULT CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC';

      ALTER TABLE IF EXISTS ONLY "oauth2_authorization_codes"
        ALTER "created_at" TYPE TIMESTAMP WITH TIME ZONE USING "created_at" AT TIME ZONE 'UTC',
        ALTER "created_at" SET DEFAULT CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC';

      ALTER TABLE IF EXISTS ONLY "oauth2_tokens"
        ALTER "created_at" TYPE TIMESTAMP WITH TIME ZONE USING "created_at" AT TIME ZONE 'UTC',
        ALTER "created_at" SET DEFAULT CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC';


      CREATE INDEX IF NOT EXISTS "oauth2_authorization_credential_id_idx" ON "oauth2_authorization_codes" ("credential_id");
      CREATE INDEX IF NOT EXISTS "oauth2_authorization_service_id_idx"    ON "oauth2_authorization_codes" ("service_id");
      CREATE INDEX IF NOT EXISTS "oauth2_authorization_api_id_idx"        ON "oauth2_authorization_codes" ("api_id");

      CREATE INDEX IF NOT EXISTS "oauth2_tokens_credential_id_idx"        ON "oauth2_tokens" ("credential_id");
      CREATE INDEX IF NOT EXISTS "oauth2_tokens_service_id_idx"           ON "oauth2_tokens" ("service_id");
      CREATE INDEX IF NOT EXISTS "oauth2_tokens_api_id_idx"               ON "oauth2_tokens" ("api_id");


      ALTER INDEX IF EXISTS "oauth2_credentials_consumer_idx" RENAME TO "oauth2_credentials_consumer_id_idx";
      ALTER INDEX IF EXISTS "oauth2_authorization_userid_idx" RENAME TO "oauth2_authorization_codes_authenticated_userid_idx";
      ALTER INDEX IF EXISTS "oauth2_token_userid_idx"         RENAME TO "oauth2_tokens_authenticated_userid_idx";

      -- Unique constraint on "client_id" already adds btree index
      DROP INDEX IF EXISTS "oauth2_credentials_client_idx";

      -- Unique constraint on "code" already adds btree index
      DROP INDEX IF EXISTS "oauth2_autorization_code_idx";

      -- Unique constraint on "access_token" already adds btree index
      DROP INDEX IF EXISTS "oauth2_accesstoken_idx";

      -- Unique constraint on "refresh_token" already adds btree index
      DROP INDEX IF EXISTS "oauth2_token_refresh_idx";
    ]],

    teardown = function(connector)
      assert(connector:query [[
        DO $$
        BEGIN
          ALTER TABLE "oauth2_credentials" DROP "redirect_uri";
        EXCEPTION WHEN UNDEFINED_COLUMN THEN
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
