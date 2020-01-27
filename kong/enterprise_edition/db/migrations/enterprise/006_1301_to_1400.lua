return {
  postgres = {
    up = [[

    ]],
    teardown = function(connector)
      -- XXX: EE keep run_on for now
      assert(connector:query([[
        DO $$
        BEGIN
          ALTER TABLE IF EXISTS ONLY "plugins" ADD "run_on" TEXT;
        EXCEPTION WHEN duplicate_column THEN
          -- Do nothing, accept existing state
        END;
        $$;
      ]]))
    end,
  },

  cassandra = {
    up = [[

    ]],
    teardown = function(connector)
      -- XXX: EE keep run_on for now
      assert(connector:query([[
        ALTER TABLE plugins ADD run_on TEXT;
      ]]))
    end,
  }
}
