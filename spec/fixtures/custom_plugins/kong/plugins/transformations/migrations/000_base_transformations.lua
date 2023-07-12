return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS "transformations" (
        "id"          UUID  PRIMARY KEY,
        "name"        TEXT,
        "secret"      TEXT,
        "hash_secret" BOOLEAN,
        "meta"        TEXT,
        "case"        TEXT
      );
    ]],
  },
}
