-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

return {
  postgres = {
    up = [[
      -- add tags to consumer_groups
      DO $$
          BEGIN
          ALTER TABLE IF EXISTS ONLY "consumer_groups" ADD tags TEXT[];
          EXCEPTION WHEN DUPLICATE_COLUMN THEN
          -- Do nothing, accept existing state
          END;
      $$;

      -- add rbac_user_name,request_source to audit_requests
      DO $$
        BEGIN
        ALTER TABLE IF EXISTS ONLY "audit_requests" ADD COLUMN "rbac_user_name" TEXT;
        ALTER TABLE IF EXISTS ONLY "audit_requests" ADD COLUMN "request_source" TEXT; 
        EXCEPTION WHEN duplicate_column THEN
          -- Do nothing, accept existing state
        END;
      $$;

      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS consumer_groups_tags_idx ON consumer_groups USING GIN(tags);
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;
      DROP TRIGGER IF EXISTS consumer_groups_sync_tags_trigger ON consumer_groups;
      DO $$
      BEGIN
        CREATE TRIGGER consumer_groups_sync_tags_trigger
        AFTER INSERT OR UPDATE OF tags OR DELETE ON consumer_groups
        FOR EACH ROW
        EXECUTE PROCEDURE sync_tags();
      EXCEPTION WHEN UNDEFINED_COLUMN OR UNDEFINED_TABLE THEN
        -- Do nothing, accept existing state
      END$$;
    ]]
  },

  cassandra = {
    up = [[
      -- add tags to consumer_groups
      ALTER TABLE consumer_groups ADD tags set<text>;
      ALTER TABLE audit_requests ADD rbac_user_name text;
      ALTER TABLE audit_requests ADD request_source text;
    ]]
  },
}
