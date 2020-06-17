return {
  postgres = {
    up = [[
      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "audit_requests" ADD removed_from_payload TEXT;
      EXCEPTION WHEN duplicate_column THEN
        -- Do nothing, accept existing state
      END;
      $$;
    ]],
    teardown = function(connector)
    end,
  },

  cassandra = {
    up = [[
      ALTER TABLE audit_requests ADD removed_from_payload TEXT;
    ]],
    teardown = function(connector)
    end,
  }
}
