return {
  postgres = {
    up = [[
      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "basicauth_credentials"
          ALTER "created_at" TYPE TIMESTAMP WITH TIME ZONE USING "created_at" AT TIME ZONE 'UTC',
          ALTER "created_at" SET DEFAULT CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC';
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;

      -- Unique constraint on "username" already adds btree index
      DROP INDEX IF EXISTS "basicauth_username_idx";
    ]],
  },

  cassandra = {
    up = [[
    ]],
  },
}
