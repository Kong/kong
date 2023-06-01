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
}
