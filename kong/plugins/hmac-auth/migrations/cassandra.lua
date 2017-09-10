return {
  {
    name = "2015-09-16-132400_init_hmacauth",
    up = [[
       CREATE TABLE IF NOT EXISTS hmacauth_credentials(
        id uuid,
        consumer_id uuid,
        username text,
        secret text,
        created_at timestamp,
        PRIMARY KEY (id)
      );

      CREATE INDEX IF NOT EXISTS ON hmacauth_credentials(username);
      CREATE INDEX IF NOT EXISTS hmacauth_consumer_id ON hmacauth_credentials(consumer_id);
    ]],
    down = [[
      DROP TABLE hmacauth_credentials;
    ]]
  },
  {
    name = "2017-06-21-132400_init_hmacauth",
    up = function(_, _, dao)
      local rows, err = dao.plugins:find_all { name = "hmac-auth" }
      if err then
        return err
      end

      for _, row in ipairs(rows) do
        row.config.validate_request_body = false
        row.config.enforce_headers = {}
        row.config.algorithms = { "hmac-sha1" }
        local _, err = dao.plugins:update(row, row)
        if err then
          return err
        end
      end
    end,
    down = function()
    end
  }
}
