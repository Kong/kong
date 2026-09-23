return {
  postgres = {
    up = [[
      DO $$
      BEGIN
      CREATE TABLE IF NOT EXISTS clustering_sync_version (
        "version" SERIAL PRIMARY KEY
      );
      END;
      $$;
    ]]
  }
}
