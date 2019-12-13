return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS keyring_meta (
        id text PRIMARY KEY,
        state text not null,
        created_at timestamp with time zone not null
      );
    ]],

    teardown = function(connector)

    end,
  },

  cassandra = {
    up = [[
      CREATE TABLE IF NOT EXISTS keyring_meta (
        id            text PRIMARY KEY,
        state         TEXT,
        created_at    timestamp
      );
      CREATE TABLE IF NOT EXISTS keyring_meta_active (
        active text PRIMARY KEY,
        id text
      );
    ]],

    teardown = function(connector)

    end,
  }
}
