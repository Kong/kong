return {
  postgres = {
    up = [[
      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "upstreams" ADD "algorithm" TEXT;
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END;
      $$;



      CREATE TABLE IF NOT EXISTS "ca_certificates" (
        "id"          UUID                       PRIMARY KEY,
        "created_at"  TIMESTAMP WITH TIME ZONE   DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        "cert"        TEXT NOT NULL,
        "tags"        TEXT[]
      );

      DO $$
      BEGIN
        CREATE TRIGGER ca_certificates_sync_tags_trigger
        AFTER INSERT OR UPDATE OF tags OR DELETE ON ca_certificates
        FOR EACH ROW
        EXECUTE PROCEDURE sync_tags();
      EXCEPTION WHEN UNDEFINED_COLUMN OR UNDEFINED_TABLE THEN
        -- Do nothing, accept existing state
      END$$;



      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "routes" ADD "headers" JSONB;
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END;
      $$;



      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "services" ADD "client_certificate_id" UUID REFERENCES "certificates" ("id");
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END;
      $$;

      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS "services_fkey_client_certificate" ON "services" ("client_certificate_id");
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;
    ]],
  },

  cassandra = {
    up = [[
      ALTER TABLE upstreams ADD algorithm text;



      CREATE TABLE IF NOT EXISTS ca_certificates(
        partition text,
        id uuid,
        cert text,
        created_at timestamp,
        tags set<text>,
        PRIMARY KEY (partition, id)
      );



      ALTER TABLE routes ADD headers map<text,frozen<set<text>>>;



      ALTER TABLE services ADD client_certificate_id uuid;
      CREATE INDEX IF NOT EXISTS services_client_certificate_id_idx ON services(client_certificate_id);
    ]],
  },
}
