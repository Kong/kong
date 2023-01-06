return {
    postgres = {
      up = [[
        DO $$
            BEGIN
            ALTER TABLE IF EXISTS ONLY "plugins" ADD "custom_name" TEXT;
            ALTER TABLE IF EXISTS ONLY "plugins" ADD CONSTRAINT "plugins_ws_id_custom_name_unique" UNIQUE ("ws_id", "custom_name");
            EXCEPTION WHEN DUPLICATE_COLUMN THEN
            -- Do nothing, accept existing state
            END;
        $$;
      ]]
    },

    cassandra = {
      up = [[
        ALTER TABLE plugins ADD custom_name text;
        CREATE INDEX IF NOT EXISTS plugins_ws_id_custom_name_idx ON plugins(custom_name);
      ]]
    },
  }
