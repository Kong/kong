return {
  {
    name = "2015-01-12-175310_skeleton",
    up = [[
      CREATE TABLE IF NOT EXISTS schema_migrations(
        id text PRIMARY KEY,
        migrations varchar(100)[]
      );
    ]],
    down = [[
      DROP TABLE schema_migrations;
    ]]
  }
}
