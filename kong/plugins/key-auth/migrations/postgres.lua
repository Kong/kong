return {
  {
    name = "2015-07-31-172400_init_keyauth",
    up = [[
      CREATE TABLE IF NOT EXISTS keyauth_credentials(
        id uuid,
        consumer_id uuid REFERENCES consumers (id) ON DELETE CASCADE,
        key text UNIQUE,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc'),
        PRIMARY KEY (id)
      );

      DO $$
      BEGIN
        IF (SELECT to_regclass('keyauth_key_idx')) IS NULL THEN
          CREATE INDEX keyauth_key_idx ON keyauth_credentials(key);
        END IF;
        IF (SELECT to_regclass('keyauth_consumer_idx')) IS NULL THEN
          CREATE INDEX keyauth_consumer_idx ON keyauth_credentials(consumer_id);
        END IF;
      END$$;
    ]],
    down = [[
      DROP TABLE keyauth_credentials;
    ]]
  },
  {
    name = "2017-07-31-120200_key-auth_preflight_default",
    up = function(_, _, dao)
      local rows, err = dao.db:query([[
        SELECT * FROM plugins WHERE name = 'key-auth';
      ]])
      if err then
        return err
      end

      for _, row in ipairs(rows) do
        local config = row.config
        if config.run_on_preflight == nil then
          config.run_on_preflight = true
          local _, err = dao.plugins:update({
            config = config,
          }, { id = row.id })
          if err then
            return err
          end
        end
      end
    end,
    down = function(_, _, dao) end  -- not implemented
  },
}
