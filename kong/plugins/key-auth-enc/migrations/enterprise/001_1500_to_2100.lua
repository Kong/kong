local operations = require "kong.enterprise_edition.db.migrations.operations.1500_to_2100"

local plugin_entities = {
  {
    name = "keyauth_enc_credentials",
    primary_key = "id",
    uniques = {"key"},
    fks = {{name = "consumer", reference = "consumers", on_delete = "cascade"}},
  }
}

return operations.ws_migrate_plugin(plugin_entities)
