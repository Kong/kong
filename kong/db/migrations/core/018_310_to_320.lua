return {
    postgres = {
      up = [[
        DO $$
            BEGIN
            ALTER TABLE IF EXISTS ONLY "upstreams" ADD "https_sni" TEXT;
            EXCEPTION WHEN DUPLICATE_COLUMN THEN
            -- Do nothing, accept existing state
            END;
        $$;
      ]]
    },

    cassandra = {
      up = [[
        ALTER TABLE upstreams ADD https_sni text;
      ]]
    },
  }
