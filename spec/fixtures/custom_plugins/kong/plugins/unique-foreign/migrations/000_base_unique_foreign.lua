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
