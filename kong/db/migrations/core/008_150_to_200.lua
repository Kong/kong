return {
  postgres = {
    up = [[
      ALTER TABLE IF EXISTS ONLY "routes" ALTER COLUMN "path_handling" SET DEFAULT 'v0';
    ]],

    teardown = function(connector)
      local _, err = connector:query([[
        DO $$
        BEGIN
          ALTER TABLE IF EXISTS ONLY "plugins" DROP COLUMN "run_on";
        EXCEPTION WHEN UNDEFINED_COLUMN THEN
          -- Do nothing, accept existing state
        END;
        $$;


        DO $$
        BEGIN
          DROP TABLE IF EXISTS "cluster_ca";
        END;
        $$;
      ]])

      if err then
        return nil, err
      end

      return true
    end,
  },
}
