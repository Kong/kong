return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS "ck_vs_ek_testcase" (
        "id"          UUID  PRIMARY KEY,
        "name"        TEXT,
        "route_id"    UUID  REFERENCES "routes" ("id") ON DELETE CASCADE,
        "service_id"  UUID  REFERENCES "services" ("id") ON DELETE CASCADE,
        "cache_key"   TEXT  UNIQUE
      );

      DO $$
      BEGIN
        CREATE UNIQUE INDEX IF NOT EXISTS "ck_vs_ek_testcase_name_idx"
          ON "ck_vs_ek_testcase" ("name");
      END$$;

      DO $$
      BEGIN
        CREATE UNIQUE INDEX IF NOT EXISTS "ck_vs_ek_testcase_cache_key_idx"
          ON "ck_vs_ek_testcase" ("cache_key");
      END$$;
    ]],
  },
}
