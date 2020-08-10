local operations = require "kong.enterprise_edition.db.migrations.operations.1500_to_2100"

local plugin_entities = {
  {
    name = "mtls_auth_credentials",
    primary_key = "id",
    uniques = {"cache_key"},
    fks = {
      {name = "consumer", reference = "consumers", on_delete = "cascade"},
      -- ca_certificates is non workspaceable
      -- {name = "ca_certificate", reference = "ca_certificates", on_delete = "cascade"}
    }
  }
}

return operations.ws_migrate_plugin(plugin_entities)
