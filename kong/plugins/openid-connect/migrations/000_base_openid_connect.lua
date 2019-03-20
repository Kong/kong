return {
  postgres = {
    up = [[

      CREATE TABLE IF NOT EXISTS oic_issuers (
        id             UUID                      PRIMARY KEY,
        issuer         TEXT                      UNIQUE,
        configuration  TEXT,
        keys           TEXT,
        secret         TEXT,
        created_at     TIMESTAMP WITH TIME ZONE  DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC')
      );

      CREATE INDEX IF NOT EXISTS "oic_issuers_idx" ON "oic_issuers" ("issuer");

    ]],
  },

  cassandra = {
    up = [[

      CREATE TABLE IF NOT EXISTS oic_issuers (
        id             uuid        PRIMARY KEY,
        issuer         text,
        configuration  text,
        keys           text,
        secret         text,
        created_at     timestamp,

        PRIMARY KEY (id)
      );

      CREATE INDEX IF NOT EXISTS ON oic_issuers (issuer);

    ]],
  },
}
