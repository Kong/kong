return {
    postgres = {
      up = [[
        DO $$
        BEGIN
          ALTER TABLE IF EXISTS ONLY "clustering_data_planes" ADD "services_accepted" JSONB;
        EXCEPTION WHEN DUPLICATE_COLUMN THEN
          -- Do nothing, accept existing state
        END;
        $$;
      ]]
    },

    cassandra = {
      up = [[
        ALTER TABLE clustering_data_planes ADD services_accepted map<text,text>;
      ]]
    },
  }
