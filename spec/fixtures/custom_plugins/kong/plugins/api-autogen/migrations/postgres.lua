return {
  {
    name = "2017-05-16-init_api_autogen",
    up = [[
      CREATE TABLE IF NOT EXISTS autogen_entities(
        id uuid,
        "name" text,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc'),
        PRIMARY KEY (id)
      );

      DO $$
      BEGIN
        IF (SELECT to_regclass('autogen_entities_name')) IS NULL THEN
          CREATE INDEX autogen_entities_name ON autogen_entities("name");
        END IF;
      END$$;
    ]],
    down = [[
      DROP TABLE autogen_entities;
    ]]
  }
}
