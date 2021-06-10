return {
  postgres = {
    up = [[
      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "clustering_data_planes" ADD "plugin_versions" JSONB[];
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END;
      $$;
    ]],
  },
  cassandra = {
    up = [[
      ALTER TABLE clustering_data_planes ADD plugin_versions text;
    ]],
  }
}
