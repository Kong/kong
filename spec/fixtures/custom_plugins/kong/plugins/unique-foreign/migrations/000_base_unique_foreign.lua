-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS "unique_foreigns" (
        "id"   UUID  PRIMARY KEY,
        "name" TEXT
      );

      CREATE TABLE IF NOT EXISTS "unique_references" (
        "id"                 UUID   PRIMARY KEY,
        "note"               TEXT,
        "unique_foreign_id"  UUID   UNIQUE        REFERENCES "unique_foreigns" ("id") ON DELETE CASCADE
      );
    ]],
  },

  cassandra = {
    up = [[
      CREATE TABLE IF NOT EXISTS unique_foreigns (
        id          uuid PRIMARY KEY,
        name        text
      );

      CREATE TABLE IF NOT EXISTS unique_references (
        id                 uuid   PRIMARY KEY,
        note               text,
        unique_foreign_id  uuid
      );

      CREATE INDEX IF NOT EXISTS ON unique_references(unique_foreign_id);
    ]],
  },
}
