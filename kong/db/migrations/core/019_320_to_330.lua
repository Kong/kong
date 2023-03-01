return {
  postgres = {
    up = [[
      DO $$
          BEGIN
          ALTER TABLE IF EXISTS ONLY "plugins" ADD "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT timezone('UTC'::text, ('now'::text)::timestamp(0) with time zone);
          ALTER TABLE IF EXISTS ONLY "ca_certificates" ADD "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT timezone('UTC'::text, ('now'::text)::timestamp(0) with time zone);
          ALTER TABLE IF EXISTS ONLY "certificates" ADD "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT timezone('UTC'::text, ('now'::text)::timestamp(0) with time zone);
          ALTER TABLE IF EXISTS ONLY "consumers" ADD "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT timezone('UTC'::text, ('now'::text)::timestamp(0) with time zone);
          ALTER TABLE IF EXISTS ONLY "snis" ADD "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT timezone('UTC'::text, ('now'::text)::timestamp(0) with time zone);
          ALTER TABLE IF EXISTS ONLY "targets" ADD "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT timezone('UTC'::text, ('now'::text)::timestamp(0) with time zone);
          ALTER TABLE IF EXISTS ONLY "upstreams" ADD "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT timezone('UTC'::text, ('now'::text)::timestamp(0) with time zone);
          EXCEPTION WHEN DUPLICATE_COLUMN THEN
            -- Do nothing, accept existing state
          END;
      $$;
    ]]
  },

  cassandra = {
    up = [[
      ALTER TABLE plugins ADD updated_at timestamp;
      ALTER TABLE ca_certificates ADD updated_at timestamp;
      ALTER TABLE certificates ADD updated_at timestamp;
      ALTER TABLE consumers ADD updated_at timestamp;
      ALTER TABLE snis ADD updated_at timestamp;
      ALTER TABLE targets ADD updated_at timestamp;
      ALTER TABLE upstreams ADD updated_at timestamp;
    ]]
  },
}
