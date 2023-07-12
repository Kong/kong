return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS "foos" (
        "color" TEXT PRIMARY KEY
      );

      INSERT INTO foos (color) values ('red');
    ]],
  },
}
