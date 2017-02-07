return {
  {
    name = "2017-01-28-000001_init_request_termination",
    up = [[
      CREATE TABLE IF NOT EXISTS request_terminations(
        id uuid,
        api_id uuid,
        status_code smallint,
        message text,
        content_type text,
        body text,
        created_at timestamp,
        PRIMARY KEY (id)
      );

      CREATE INDEX IF NOT EXISTS ON request_terminations(group);
      CREATE INDEX IF NOT EXISTS request_terminations_api_id ON request_terminations(api_id);
    ]],
    down = [[
      DROP TABLE request_terminations;
    ]]
  }
}
