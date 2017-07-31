return {
  {
    name = "2015-07-31-172400_init_keyauth",
    up =  [[
      CREATE TABLE IF NOT EXISTS keyauth_credentials(
        id uuid,
        consumer_id uuid,
        key text,
        created_at timestamp,
        PRIMARY KEY (id)
      );

      CREATE INDEX IF NOT EXISTS ON keyauth_credentials(key);
      CREATE INDEX IF NOT EXISTS keyauth_consumer_id ON keyauth_credentials(consumer_id);
    ]],
    down = [[
      DROP TABLE keyauth_credentials;
    ]]
  },
  {
    name = "2017-07-31-120200_key-auth_preflight_default",
    up = function(_, _, dao)
      for rows, err in dao.db.cluster:iterate([[
                          SELECT * FROM plugins WHERE name = 'key-auth';
                        ]]) do
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
      end
    end,
    down = function(_, _, dao) end  -- not implemented
  },
}
