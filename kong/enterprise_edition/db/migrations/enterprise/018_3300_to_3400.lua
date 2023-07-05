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
          ALTER TABLE IF EXISTS ONLY "plugins" ADD COLUMN "consumer_group_id" UUID REFERENCES "consumer_groups" ("id") ON DELETE CASCADE;
          EXCEPTION WHEN DUPLICATE_COLUMN THEN
            -- Do nothing, accept existing state
          END;
      $$;

      DO $$
          DECLARE
            tablename TEXT;
          BEGIN
          FOR tablename IN (
            SELECT c.table_name
            FROM information_schema.columns c
            WHERE column_name = 'ws_id' and table_name in ('upstreams','targets','consumers','certificates','snis','services','routes','plugins','sm_vaults','key_sets','keys','acls','basicauth_credentials','hmacauth_credentials','jwt_secrets','keyauth_credentials','oauth2_credentials','oauth2_authorization_codes','oauth2_tokens','rbac_users','rbac_roles','files','developers','document_objects','applications','application_instances','consumer_groups','consumer_group_plugins')
          )
          LOOP
            EXECUTE format('ALTER TABLE IF EXISTS ONLY "%I" DROP CONSTRAINT IF EXISTS "%I_ws_id_fkey"', tablename, tablename);
            EXECUTE format('ALTER TABLE IF EXISTS ONLY "%I" ADD CONSTRAINT "%I_ws_id_fkey" FOREIGN KEY ("ws_id") REFERENCES "workspaces" ("id") ON DELETE CASCADE ON UPDATE NO ACTION', tablename, tablename);
          END LOOP;
      END
      $$;

    ]]
  },
}
