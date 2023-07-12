return {
  postgres = {
    up = [[
      DROP TRIGGER IF EXISTS "keyauth_credentials_ttl_trigger" ON "keyauth_credentials";

      DO $$
      BEGIN
        CREATE TRIGGER "keyauth_credentials_ttl_trigger"
        AFTER INSERT ON "keyauth_credentials"
        FOR EACH STATEMENT
        EXECUTE PROCEDURE batch_delete_expired_rows("ttl");
      EXCEPTION WHEN UNDEFINED_COLUMN OR UNDEFINED_TABLE THEN
        -- Do nothing, accept existing state
      END$$;
    ]],
  },
}
