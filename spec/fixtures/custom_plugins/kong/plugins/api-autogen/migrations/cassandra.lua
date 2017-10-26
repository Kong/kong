return {
  {
    name = "2017-05-16-init_api_autogen",
    up = [[
      CREATE TABLE IF NOT EXISTS autogen_entities(
        id uuid,
        name text,
        created_at timestamp,
        PRIMARY KEY (id)
      );

      CREATE INDEX IF NOT EXISTS ON autogen_entities(name);
    ]],
    down = [[
      DROP TABLE autogen_entities;
    ]]
  }
}
