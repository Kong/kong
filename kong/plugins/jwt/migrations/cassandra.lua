return {
  {
    name = "2015-06-09-jwt-auth",
    up = [[
      CREATE TABLE IF NOT EXISTS jwt_secrets(
        id uuid,
        consumer_id uuid,
        key text,
        secret text,
        created_at timestamp,
        PRIMARY KEY (id)
      );

      CREATE INDEX IF NOT EXISTS ON jwt_secrets(key);
      CREATE INDEX IF NOT EXISTS ON jwt_secrets(secret);
      CREATE INDEX IF NOT EXISTS ON jwt_secrets(consumer_id);
    ]],
    down = [[
      DROP TABLE jwt_secrets;
    ]]
  },
  {
    name = "2016-03-07-jwt-alg",
    up = [[
      ALTER TABLE jwt_secrets ADD algorithm text;
      ALTER TABLE jwt_secrets ADD rsa_public_key text;
    ]],
    down = [[
      ALTER TABLE jwt_secrets DROP algorithm;
      ALTER TABLE jwt_secrets DROP rsa_public_key;
    ]]
  },
  {
    name = "2017-07-31-113200_jwt_preflight_default",
    up = function(_, _, dao)
      for rows, err in dao.db.cluster:iterate([[
                          SELECT * FROM plugins WHERE name = 'jwt';
                        ]]) do
        if err then
          return err
        end

        for _, row in ipairs(rows) do
          if row.config.run_on_preflight == nil then
            local _, err = dao.apis:update({
              run_on_preflight = true,
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
