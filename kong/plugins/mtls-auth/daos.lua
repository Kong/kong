local typedefs = require "kong.db.schema.typedefs"

return {
  mtls_auth_credentials = {
    primary_key = { "id" },
    name = "mtls_auth_credentials",
    cache_key = { "subject_name", "certificate_authority", },
    workspaceable = true,
    fields = {
      { id = typedefs.uuid },
      { created_at = typedefs.auto_timestamp_s },
      { consumer = { type = "foreign", reference = "consumers", default = ngx.null, on_delete = "cascade", }, },
      { subject_name = { type = "string", required = true, }, },
      { certificate_authority = { type = "string", uuid = true, default = ngx.null, required = false, }, },
    },
  },
}

