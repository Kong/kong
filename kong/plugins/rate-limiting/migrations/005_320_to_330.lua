return {
  postgres = {
    up = [[
      DROP TRIGGER IF EXISTS "ratelimiting_metrics_ttl_trigger" ON "ratelimiting_metrics";

      DO $$
      BEGIN
        CREATE TRIGGER "ratelimiting_metrics_ttl_trigger"
        AFTER INSERT ON "ratelimiting_metrics"
        FOR EACH STATEMENT
        EXECUTE PROCEDURE batch_delete_expired_rows("ttl");
      EXCEPTION WHEN UNDEFINED_COLUMN OR UNDEFINED_TABLE THEN
        -- Do nothing, accept existing state
      END$$;
    ]],
  },
}
