return {
  {
    name = "2017-01-28-000001_init_request_termination",
    up = [[
      CREATE TABLE IF NOT EXISTS request_terminations(
        id uuid,
        api_id uuid REFERENCES apis (id) ON DELETE CASCADE,
        status_code smallint,
        message text,
        content_type text,
        body text,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc'),
        PRIMARY KEY (id)
      );

      DO $$
      BEGIN
        IF (SELECT to_regclass('request_terminations_api_id')) IS NULL THEN
          CREATE INDEX request_terminations_api_id ON request_terminations(api_id);
        END IF;
      END$$;
    ]],
    down = [[
      DROP TABLE request_terminations;
    ]]
  }
}
