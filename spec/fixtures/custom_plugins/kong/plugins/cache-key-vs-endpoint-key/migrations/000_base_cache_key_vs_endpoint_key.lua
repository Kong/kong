-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

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
