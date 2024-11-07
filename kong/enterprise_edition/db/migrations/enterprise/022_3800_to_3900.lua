-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

return {
  postgres = {
    up = [[
      DO $$
      BEGIN
      ALTER TABLE basicauth_credentials DROP CONSTRAINT IF EXISTS basicauth_credentials_consumer_id_fkey;
      ALTER TABLE keyauth_credentials DROP CONSTRAINT IF EXISTS keyauth_credentials_consumer_id_fkey;

      ALTER TABLE IF EXISTS ONLY "basicauth_credentials"
      ADD CONSTRAINT "basicauth_credentials_consumer_id_fkey"
      FOREIGN KEY ("consumer_id")
      REFERENCES consumers("id") ON DELETE CASCADE;

      ALTER TABLE IF EXISTS ONLY "keyauth_credentials"
      ADD CONSTRAINT "keyauth_credentials_consumer_id_fkey"
      FOREIGN KEY ("consumer_id")
      REFERENCES consumers("id") ON DELETE CASCADE;
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END;
      $$;
    ]]
  }
}
