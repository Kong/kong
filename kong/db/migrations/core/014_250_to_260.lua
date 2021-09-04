return {
  postgres = {
    up = [[
        DO $$
          BEGIN
            ALTER TABLE IF EXISTS ONLY certificates ADD COLUMN "tls_verify" BOOLEAN;
          EXCEPTION WHEN duplicate_column THEN
            -- Do nothing, accept existing state
          END;
        $$;

        DO $$
          BEGIN
            ALTER TABLE IF EXISTS ONLY certificates ADD COLUMN "tls_verify_depth" SMALLINT;
          EXCEPTION WHEN duplicate_column THEN
            -- Do nothing, accept existing state
          END;
        $$;

        DO $$
          BEGIN
            ALTER TABLE IF EXISTS ONLY certificates ADD COLUMN "ca_certificates" UUID[];
          EXCEPTION WHEN duplicate_column THEN
            -- Do nothing, accept existing state
          END;
        $$;
    ]]
  },
  cassandra = {
    up = [[
      ALTER TABLE certificates ADD tls_verify boolean;
      ALTER TABLE certificates ADD tls_verify_depth int;
      ALTER TABLE certificates ADD ca_certificates set<uuid>;
    ]]
  }
}
