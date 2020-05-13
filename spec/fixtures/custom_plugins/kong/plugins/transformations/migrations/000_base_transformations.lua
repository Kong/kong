return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS "transformations" (
        "id"          UUID  PRIMARY KEY,
        "name"        TEXT,
        "secret"      TEXT,
        "hash_secret" BOOLEAN
      );
    ]],
  },

  cassandra = {
    up = [[
      CREATE TABLE IF NOT EXISTS transformations (
        id          uuid PRIMARY KEY,
        name        text,
        secret      text,
        hash_secret boolean
      );
    ]],
  },
}
