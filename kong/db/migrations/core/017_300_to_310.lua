return {
    postgres = {
      up = [[
        DO $$
            BEGIN
            ALTER TABLE IF EXISTS ONLY "upstreams" ADD "use_srv_name"  BOOLEAN DEFAULT false;
            EXCEPTION WHEN DUPLICATE_COLUMN THEN
            -- Do nothing, accept existing state
            END;
        $$;
      ]]
    },
  
    cassandra = {
      up = [[
        ALTER TABLE upstreams ADD use_srv_name boolean;
      ]]
    },
  }
  