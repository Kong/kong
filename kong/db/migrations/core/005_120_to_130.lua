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
        "cert"        TEXT NOT NULL              UNIQUE,
        "tags"        TEXT[]
      );

      DROP TRIGGER IF EXISTS ca_certificates_sync_tags_trigger ON ca_certificates;

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
    teardown = function(connector)
      assert(connector:connect_migrations())
      for upstream, err in connector:iterate([[SELECT * FROM "upstreams";]]) do
        if err then
          return nil, err
        end

        if type(upstream.algorithm) == "string" and #upstream.algorithm > 0 then
          goto continue
        end

        local algorithm
        if upstream.hash_on == "none" then
          algorithm = "round-robin"
        else
          algorithm = "consistent-hashing"
        end
        local update_query = string.format([[
          UPDATE "upstreams"
          SET "algorithm" = '%s'
          WHERE "id" = '%s';
        ]], algorithm, upstream.id)

        local _, err = connector:query(update_query)
        if err then
          return nil, err
        end

        ::continue::
      end
    end,

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

      CREATE INDEX IF NOT EXISTS ca_certificates_cert_idx ON ca_certificates(cert);



      ALTER TABLE routes ADD headers map<text,frozen<set<text>>>;



      ALTER TABLE services ADD client_certificate_id uuid;
      CREATE INDEX IF NOT EXISTS services_client_certificate_id_idx ON services(client_certificate_id);
    ]],
    teardown = function(connector)
      local cassandra = require "cassandra"
      local coordinator = assert(connector:connect_migrations())

      for rows, err in coordinator:iterate([[SELECT * FROM upstreams;]]) do
        if err then
          return nil, err
        end

        for i = 1, #rows do
          local upstream = rows[i]
          if type(upstream.algorithm) == "string" and #upstream.algorithm > 0 then
            goto continue
          end

          local algorithm
          if upstream.hash_on == "none" then
            algorithm = "round-robin"
          else
            algorithm = "consistent-hashing"
          end

          local _, err = connector:query([[
            UPDATE upstreams
            SET algorithm = ?
            WHERE id = ?
          ]], {
            algorithm,
            cassandra.uuid(upstream.id),
          })
          if err then
            return nil, err
          end

          ::continue::
        end

      end
    end,

  },
}
