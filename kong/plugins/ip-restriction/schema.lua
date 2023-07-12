local typedefs = require "kong.db.schema.typedefs"


return {
  name = "ip-restriction",
  fields = {
    { protocols = typedefs.protocols { default = { "http", "https", "tcp", "tls", "grpc", "grpcs" } }, },
    { config = {
        type = "record",
        fields = {
          { allow = { description = "List of IPs or CIDR ranges to allow. One of `config.allow` or `config.deny` must be specified.", type = "array", elements = typedefs.ip_or_cidr, }, },
          { deny = { description = "List of IPs or CIDR ranges to deny. One of `config.allow` or `config.deny` must be specified.", type = "array", elements = typedefs.ip_or_cidr, }, },
          { status = { description = "The HTTP status of the requests that will be rejected by the plugin.", type = "number", required = false } },
          { message = { description = "The message to send as a response body to rejected requests.", type = "string", required = false } },
        },
      },
    },
  },
  entity_checks = {
    { at_least_one_of = { "config.allow", "config.deny" }, },
  },
}
