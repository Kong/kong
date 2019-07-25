local typedefs = require "kong.db.schema.typedefs"

return {
  mtls_auth_credentials = {
    primary_key = { "id" },
    name = "mtls_auth_credentials",
    cache_key = { "subject_name", "ca_certificate", },
    workspaceable = true,
    fields = {
      { id = typedefs.uuid },
      { created_at = typedefs.auto_timestamp_s },
      { consumer = { type = "foreign", reference = "consumers", on_delete = "cascade", }, },
      { subject_name = { type = "string", required = true, }, },
      { ca_certificate = { type = "foreign", reference = "ca_certificates", default = ngx.null, on_delete = "cascade", }, },
    },
  },
}

