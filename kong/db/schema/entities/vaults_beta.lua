local typedefs = require "kong.db.schema.typedefs"


return {
  name = "vaults_beta",
  primary_key = { "id" },
  cache_key = { "prefix" },
  endpoint_key = "prefix",
  workspaceable = true,
  subschema_key = "name",
  subschema_error = "vault '%s' is not installed",
  admin_api_name = "vaults-beta",
  dao = "kong.db.dao.vaults",
  fields = {
    { id = typedefs.uuid },
    -- note: prefix must be valid in a host part of vault reference uri:
    -- {vault://<vault-prefix>/<secret-id>[/<secret-key]}
    { prefix = { type = "string", required = true, unique = true, unique_across_ws = true,
                 match = [[^[a-z][a-z%d-]-[a-z%d]+$]] }},
    { name = { type = "string", required = true }},
    { description = { type = "string" }},
    { config = { type = "record", abstract = true }},
    { created_at = typedefs.auto_timestamp_s },
    { updated_at = typedefs.auto_timestamp_s },
    { tags = typedefs.tags },
  },
}
