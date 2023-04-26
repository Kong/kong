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
          ALTER TABLE IF EXISTS ONLY "consumer_group_consumers" ADD "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC');
          ALTER TABLE IF EXISTS ONLY "consumer_group_plugins" ADD "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC');
          ALTER TABLE IF EXISTS ONLY "consumer_groups" ADD "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC');
          ALTER TABLE IF EXISTS ONLY "credentials" ADD "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC');
          ALTER TABLE IF EXISTS ONLY "event_hooks" ADD "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC');
          ALTER TABLE IF EXISTS ONLY "files" ADD "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC');
          ALTER TABLE IF EXISTS ONLY "group_rbac_roles" ADD "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC');
          ALTER TABLE IF EXISTS ONLY "groups" ADD "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC');
          ALTER TABLE IF EXISTS ONLY "keyring_meta" ADD "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC');
          ALTER TABLE IF EXISTS ONLY "legacy_files" ADD "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC');
          ALTER TABLE IF EXISTS ONLY "login_attempts" ADD "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC');
          ALTER TABLE IF EXISTS ONLY "parameters" ADD "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC');
          ALTER TABLE IF EXISTS ONLY "rbac_role_endpoints" ADD "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC');
          ALTER TABLE IF EXISTS ONLY "rbac_role_entities" ADD "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC');
          ALTER TABLE IF EXISTS ONLY "rbac_roles" ADD "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC');
          ALTER TABLE IF EXISTS ONLY "rbac_users" ADD "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC');
          EXCEPTION WHEN DUPLICATE_COLUMN THEN
            -- Do nothing, accept existing state
          END;
      $$;
    ]]
  },

  cassandra = {
    up = [[
      ALTER TABLE consumer_group_consumers ADD updated_at timestamp;
      ALTER TABLE consumer_group_plugins ADD updated_at timestamp;
      ALTER TABLE consumer_groups ADD updated_at timestamp;
      ALTER TABLE credentials ADD updated_at timestamp;
      ALTER TABLE event_hooks ADD updated_at timestamp;
      ALTER TABLE files ADD updated_at timestamp;
      ALTER TABLE group_rbac_roles ADD updated_at timestamp;
      ALTER TABLE groups ADD updated_at timestamp;
      ALTER TABLE keyring_meta ADD updated_at timestamp;
      ALTER TABLE legacy_files ADD updated_at timestamp;
      ALTER TABLE login_attempts ADD updated_at timestamp;
      ALTER TABLE parameters ADD updated_at timestamp;
      ALTER TABLE rbac_role_endpoints ADD updated_at timestamp;
      ALTER TABLE rbac_role_entities ADD updated_at timestamp;
      ALTER TABLE rbac_roles ADD updated_at timestamp;
      ALTER TABLE rbac_users ADD updated_at timestamp;
    ]]
  },
}