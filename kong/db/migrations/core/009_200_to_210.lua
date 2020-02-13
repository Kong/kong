return {
  postgres = {
    up = [[
       DO $$
       BEGIN
         ALTER TABLE IF EXISTS ONLY "services" ADD
             "x_forwarded_proto" TEXT,
             "x_forwarded_host" TEXT,
             "x_forwarded_port" INT;
       EXCEPTION WHEN UNDEFINED_COLUMN THEN
         -- Do nothing, accept existing state
       END$$;
    ]],
  },

  cassandra = {
    up = [[
      ALTER TABLE services ADD x_forwarded_proto text;
      ALTER TABLE services ADD x_forwarded_host text;
      ALTER TABLE services ADD x_forwarded_port int;
    ]],
  },
}
