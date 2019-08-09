return {
  postgres = {
    up = [[
      ALTER TABLE files
        ADD COLUMN checksum text;

      ALTER TABLE files
        ADD COLUMN path text UNIQUE NOT NULL;

      CREATE TABLE IF NOT EXISTS legacy_files(
        id uuid PRIMARY KEY,
        auth boolean NOT NULL,
        name text UNIQUE NOT NULL,
        type text NOT NULL,
        contents text,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc')
      );

      DO $$
      BEGIN
        ALTER TABLE developers ADD rbac_user_id uuid;
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END;
      $$;

      CREATE INDEX IF NOT EXISTS developers_rbac_user_id_idx ON developers(rbac_user_id);
    ]],
    teardown = function(connector)
      assert(connector:connect_migrations())

      -- remove unneccesssary columns in files
      assert(connector:query([[
        ALTER TABLE files DROP COLUMN IF EXISTS auth;
        ALTER TABLE files DROP COLUMN IF EXISTS name;
        ALTER TABLE files DROP COLUMN IF EXISTS type;
      ]]))
    end
  },

  cassandra = {
    up = [[
      ALTER TABLE files ADD checksum text;
      ALTER TABLE files ADD path text;
      CREATE INDEX IF NOT EXISTS ON files(path);

      CREATE TABLE IF NOT EXISTS legacy_files(
        id uuid PRIMARY KEY,
        auth boolean,
        name text,
        type text,
        contents text,
        created_at timestamp
      );

      CREATE INDEX IF NOT EXISTS ON legacy_files(name);
      CREATE INDEX IF NOT EXISTS ON legacy_files(type);

      ALTER TABLE developers ADD rbac_user_id uuid;
      CREATE INDEX IF NOT EXISTS ON developers(rbac_user_id);
    ]],
    teardown = function(connector)
      -- remove unneccesssary columns in files
      assert(connector:query([[
        DROP INDEX IF EXISTS files_name_idx;
        DROP INDEX IF EXISTS files_type_idx;

        ALTER TABLE files DROP auth;
        ALTER TABLE files DROP name;
        ALTER TABLE files DROP type;
      ]]))
    end
  },
}
