-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

return {
  postgres = {
    up = [[
      DROP TRIGGER IF EXISTS "oauth2_authorization_codes_ttl_trigger" ON "oauth2_authorization_codes";

      DO $$
      BEGIN
        CREATE TRIGGER "oauth2_authorization_codes_ttl_trigger"
        AFTER INSERT ON "oauth2_authorization_codes"
        FOR EACH STATEMENT
        EXECUTE PROCEDURE batch_delete_expired_rows("ttl");
      EXCEPTION WHEN UNDEFINED_COLUMN OR UNDEFINED_TABLE THEN
        -- Do nothing, accept existing state
      END$$;


      DROP TRIGGER IF EXISTS "oauth2_tokens_ttl_trigger" ON "oauth2_tokens";

      DO $$
      BEGIN
        CREATE TRIGGER "oauth2_tokens_ttl_trigger"
        AFTER INSERT ON "oauth2_tokens"
        FOR EACH STATEMENT
        EXECUTE PROCEDURE batch_delete_expired_rows("ttl");
      EXCEPTION WHEN UNDEFINED_COLUMN OR UNDEFINED_TABLE THEN
        -- Do nothing, accept existing state
      END$$;
    ]],
  },
}
