-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS "foreign_entities" (
        "id"    UUID   PRIMARY KEY,
        "name"  TEXT   UNIQUE,
        "same"  UUID
      );

      CREATE TABLE IF NOT EXISTS "foreign_references" (
        "id"       UUID   PRIMARY KEY,
        "name"     TEXT   UNIQUE,
        "same_id"  UUID   REFERENCES "foreign_entities" ("id") ON DELETE CASCADE
      );

      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS "foreign_references_fkey_same" ON "foreign_references" ("same_id");
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;
    ]],
  },

  cassandra = {
    up = [[
      CREATE TABLE IF NOT EXISTS foreign_entities (
        id    uuid   PRIMARY KEY,
        name  text,
        same  uuid
      );

      CREATE INDEX IF NOT EXISTS ON foreign_entities(name);

      CREATE TABLE IF NOT EXISTS foreign_references (
        id       uuid   PRIMARY KEY,
        name     text,
        same_id  uuid
      );

      CREATE INDEX IF NOT EXISTS ON foreign_references (name);
      CREATE INDEX IF NOT EXISTS ON foreign_references (same_id);
    ]],
  },
}
