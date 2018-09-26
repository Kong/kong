return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS "foos" (
        "color" TEXT PRIMARY KEY
      );
    ]],
  },

  cassandra = {
    up = [[
      CREATE TABLE IF NOT EXISTS foos (
        color text PRIMARY KEY
      );
    ]],
  },
}
