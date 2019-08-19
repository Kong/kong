return {
  postgres = {
    up = [[
    ]],

    teardown = function(connector)
      assert(connector:connect_migrations())
      assert(connector:query [[
        DROP INDEX IF EXISTS "oauth2_authorization_api_id_idx";
        DROP INDEX IF EXISTS "oauth2_tokens_api_id_idx";


        DO $$
        BEGIN
          ALTER TABLE IF EXISTS ONLY "oauth2_authorization_codes" DROP "api_id";
        EXCEPTION WHEN UNDEFINED_COLUMN THEN
          -- Do nothing, accept existing state
        END$$;


        DO $$
        BEGIN
          ALTER TABLE IF EXISTS ONLY "oauth2_tokens" DROP "api_id";
        EXCEPTION WHEN UNDEFINED_COLUMN THEN
          -- Do nothing, accept existing state
        END$$;
      ]])
    end,
  },

  cassandra = {
    up = [[
    ]],

    teardown = function(connector)
      assert(connector:connect_migrations())
      assert(connector:query([[
        DROP INDEX IF EXISTS oauth2_authorization_codes_api_id_idx;
        DROP INDEX IF EXISTS oauth2_tokens_api_id_idx;
      ]]))


      local _, err = connector:query([[
        ALTER TABLE oauth2_authorization_codes DROP api_id]])
      if err and not (string.find(err, "Column .- was not found in table") or
                      string.find(err, "[Ii]nvalid column name")           or
                      string.find(err, "[Uu]ndefined column name")) then
        return nil, err
      end

      _, err = connector:query("ALTER TABLE oauth2_tokens DROP api_id")
      if err and not (string.find(err, "Column .- was not found in table") or
                      string.find(err, "[Ii]nvalid column name")           or
                      string.find(err, "[Uu]ndefined column name")) then
        return nil, err
      end
    end,
  },
}
