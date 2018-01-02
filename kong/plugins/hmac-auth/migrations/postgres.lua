return {
  {
    name = "2015-09-16-132400_init_hmacauth",
    up = [[
       CREATE TABLE IF NOT EXISTS hmacauth_credentials(
        id uuid,
        consumer_id uuid REFERENCES consumers (id) ON DELETE CASCADE,
        username text UNIQUE,
        secret text,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc'),
        PRIMARY KEY (id)
      );

      DO $$
      BEGIN
        IF (SELECT to_regclass('hmacauth_credentials_username')) IS NULL THEN
          CREATE INDEX hmacauth_credentials_username ON hmacauth_credentials(username);
        END IF;
        IF (SELECT to_regclass('hmacauth_credentials_consumer_id')) IS NULL THEN
          CREATE INDEX hmacauth_credentials_consumer_id ON hmacauth_credentials(consumer_id);
        END IF;
      END$$;
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
        row.config.algorithms = {"hmac-sha1"}
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
