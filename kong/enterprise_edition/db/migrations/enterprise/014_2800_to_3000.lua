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
          ALTER TABLE IF EXISTS ONLY "plugins" ADD "ordering" jsonb;
        EXCEPTION WHEN DUPLICATE_COLUMN THEN
          -- Do nothing, accept existing state
        END;
        $$;

        CREATE TABLE IF NOT EXISTS keyring_keys (
            id text PRIMARY KEY,
            recovery_key_id text not null,
            key_encrypted text not null,
            created_at timestamp with time zone not null,
            updated_at timestamp with time zone not null
        );
      ]]
    },

    cassandra = {
      up = [[
        ALTER TABLE plugins ADD ordering TEXT;

        CREATE TABLE IF NOT EXISTS keyring_keys (
            id                  text PRIMARY KEY,
            recovery_key_id     text,
            key_encrypted       text,
            created_at          timestamp,
            updated_at          timestamp
          );
      ]]
    }
}
