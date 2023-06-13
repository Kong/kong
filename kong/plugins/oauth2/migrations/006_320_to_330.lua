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
