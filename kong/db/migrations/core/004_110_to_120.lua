return {
  postgres = {
    up = [[
      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS cluster_events_expire_at_idx ON cluster_events(expire_at);
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;

      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "routes" ADD "https_redirect_status_code" INTEGER;
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END;
      $$;
    ]],
  },

  cassandra = {
    up = [[
      ALTER TABLE routes ADD https_redirect_status_code int;
    ]],
  },
}
