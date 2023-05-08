return {
  postgres = {
    up = [[
      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "oauth2_authorization_codes" ADD "plugin_id" UUID REFERENCES "plugins" ("id") ON DELETE CASCADE;
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;
    ]],
  },

  cassandra = {
    up = [[
      ALTER TABLE oauth2_authorization_codes ADD plugin_id uuid;
      CREATE INDEX IF NOT EXISTS ON oauth2_authorization_codes(plugin_id);
    ]],
  },
}
