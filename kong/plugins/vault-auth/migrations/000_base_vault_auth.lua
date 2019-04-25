return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS "vaults" (
        "id"               UUID                       PRIMARY KEY,
        "created_at"       TIMESTAMP WITH TIME ZONE,
        "updated_at"       TIMESTAMP WITH TIME ZONE,
        "name"             TEXT                       UNIQUE,
        "protocol"         TEXT,
        "host"             TEXT,
        "port"             BIGINT,
        "mount"            TEXT,
        "vault_token"      TEXT
      );
    ]],
  },
  cassandra = {
    up = [[
      CREATE TABLE IF NOT EXISTS vaults(
        id          uuid,
        created_at  timestamp,
        updated_at  timestamp,
        name        text,
        protocol    text,
        host        text,
        port        int,
        mount       text,
        vault_token text,
        PRIMARY KEY (id)
      );
    ]],
  },
}
