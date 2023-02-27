return {
    postgres = {
      up = [[
        DO $$
            BEGIN
            ALTER TABLE IF EXISTS ONLY "key_sets" ADD "jwks_url" TEXT;
            EXCEPTION WHEN DUPLICATE_COLUMN THEN
            -- Do nothing, accept existing state
            END;
        $$;
      ]]
    },
  }
