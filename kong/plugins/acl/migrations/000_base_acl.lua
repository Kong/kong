return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS "acls" (
        "id"           UUID                         PRIMARY KEY,
        "created_at"   TIMESTAMP WITHOUT TIME ZONE  DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        "kongsumer_id"  UUID                         REFERENCES "kongsumers" ("id") ON DELETE CASCADE,
        "group"        TEXT
      );

      CREATE INDEX IF NOT EXISTS "acls_kongsumer_id" ON "acls" ("kongsumer_id");
      CREATE INDEX IF NOT EXISTS "acls_group"       ON "acls" ("group");
    ]],
  },

  cassandra = {
    up = [[
      CREATE TABLE IF NOT EXISTS acls(
        id          uuid PRIMARY KEY,
        created_at  timestamp,
        kongsumer_id uuid,
        group       text
      );
      CREATE INDEX IF NOT EXISTS ON acls(group);
      CREATE INDEX IF NOT EXISTS ON acls(kongsumer_id);
    ]],
  },
}
