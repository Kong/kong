return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS "cluster_events" (
        "id"         UUID                       PRIMARY KEY,
        "node_id"    UUID                       NOT NULL,
        "at"         TIMESTAMP WITH TIME ZONE   NOT NULL,
        "nbf"        TIMESTAMP WITH TIME ZONE,
        "expire_at"  TIMESTAMP WITH TIME ZONE   NOT NULL,
        "channel"    TEXT,
        "data"       TEXT
      );
      CREATE TABLE IF NOT EXISTS "consumers" (
        "id"         UUID                       PRIMARY KEY
      );
    ]]
  },
  cassandra = {
    up = [[
      CREATE TABLE IF NOT EXISTS cluster_events(
        channel text,
        at      timestamp,
        node_id uuid,
        id      uuid,
        data    text,
        nbf     timestamp,
        PRIMARY KEY (channel, at, node_id, id)
      ) WITH default_time_to_live = 86400;
      CREATE TABLE IF NOT EXISTS consumers (
        id      uuid,
        PRIMARY KEY (id)
      );
    ]],
  }
}
