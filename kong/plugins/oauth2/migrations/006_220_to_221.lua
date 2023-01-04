return {
  postgres = {
    up = [[
      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "oauth2_authorization_codes" ADD "plugin_identifer" TEXT;
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;
    ]],
  },

  cassandra = {
    up = [[
      ALTER TABLE oauth2_authorization_codes ADD plugin_identifer text;
    ]],
  },
}
