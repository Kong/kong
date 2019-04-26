return {
  postgres = {
    up = [[
      -- 2018-05-17-173100_hash_on_cookie
      DO $$
      BEGIN
        ALTER TABLE upstreams ADD hash_on_cookie text;
        ALTER TABLE upstreams ADD hash_on_cookie_path text;
      EXCEPTION WHEN duplicate_column THEN
        -- Do nothing, accept existing state
      END$$;

    ]],

    teardown = function(connector, helpers)
    end,
  },

  cassandra = {
    up = [[
      -- 2018-05-17-173100_hash_on_cookie
      ALTER TABLE upstreams ADD hash_on_cookie text;
      ALTER TABLE upstreams ADD hash_on_cookie_path text;
    ]],

    teardown = function(connector, helpers)

    end,
  },
}
