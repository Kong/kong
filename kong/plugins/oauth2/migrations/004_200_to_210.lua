local operations = require "kong.db.migrations.operations.200_to_210"


local plugin_entities = {
  {
    name = "oauth2_credentials",
    primary_key = "id",
    uniques = {"client_id"},
    fks = {{name = "consumer", reference = "consumers", on_delete = "cascade"}},
  },
  {
    name = "oauth2_authorization_codes",
    primary_key = "id",
    uniques = {"code"},
    fks = {
      {name = "service", reference = "services", on_delete = "cascade"},
      {name = "credential", reference = "oauth2_credentials", on_delete = "cascade"},
    },
  },
  {
    name = "oauth2_tokens",
    primary_key = "id",
    uniques = {"access_token", "refresh_token"},
    fks = {
      {name = "service", reference = "services", on_delete = "cascade"},
      {name = "credential", reference = "oauth2_credentials", on_delete = "cascade"},
    }
  },
}


local function ws_migration_up(ops)
  return ops:ws_adjust_fields(plugin_entities)
end


local function ws_migration_teardown(ops)
  return function(connector)
    return ops:ws_adjust_data(connector, plugin_entities)
  end
end


return {
  postgres = {
    up = [[
      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "oauth2_authorization_codes" ADD "challenge" TEXT;
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;

      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "oauth2_authorization_codes" ADD "challenge_method" TEXT;
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;

      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "oauth2_credentials" ADD "client_type" TEXT;
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;

      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY oauth2_credentials ADD hash_secret BOOLEAN;
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;
    ]] .. assert(ws_migration_up(operations.postgres.up)),

    teardown = ws_migration_teardown(operations.postgres.teardown),
  },

  cassandra = {
    up = [[
      ALTER TABLE oauth2_authorization_codes ADD challenge text;
      ALTER TABLE oauth2_authorization_codes ADD challenge_method text;
      ALTER TABLE oauth2_credentials ADD client_type text;
      ALTER TABLE oauth2_credentials ADD hash_secret boolean;
    ]] .. assert(ws_migration_up(operations.cassandra.up)),

    teardown = ws_migration_teardown(operations.cassandra.teardown),
  },
}
