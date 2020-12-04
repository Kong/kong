local utils = require("kong.tools.utils")


local CLUSTER_ID = utils.uuid()


return {
  postgres = {
    up = string.format([[
      CREATE TABLE IF NOT EXISTS "parameters" (
        key            TEXT PRIMARY KEY,
        value          TEXT NOT NULL,
        created_at     TIMESTAMP WITH TIME ZONE
      );

      INSERT INTO parameters (key, value) VALUES('cluster_id', '%s')
      ON CONFLICT DO NOTHING;
    ]], CLUSTER_ID),
  },
  cassandra = {
    up = string.format([[
      CREATE TABLE IF NOT EXISTS parameters(
        key            text,
        value          text,
        created_at     timestamp,
        PRIMARY KEY    (key)
      );

      INSERT INTO parameters (key, value) VALUES('cluster_id', '%s')
      IF NOT EXISTS;
    ]], CLUSTER_ID),
  }
}
