local typedefs = require "kong.db.schema.typedefs"


return {
  name         = "routes",
  primary_key  = { "id" },
  endpoint_key = "name",
  workspaceable = true,
  subschema_key = "protocols",

  fields = {
    { id             = typedefs.uuid, },
    { created_at     = typedefs.auto_timestamp_s },
    { updated_at     = typedefs.auto_timestamp_s },
    { name           = typedefs.utf8_name },
    { protocols      = { type     = "set",
                         len_min  = 1,
                         required = true,
                         elements = typedefs.protocol,
                         mutually_exclusive_subsets = {
                           { "http", "https" },
                           { "tcp", "tls", "udp" },
                           { "tls_passthrough" },
                           { "grpc", "grpcs" },
                         },
                         default = { "http", "https" }, -- TODO: different default depending on service's scheme
                       }, },
    { methods        = typedefs.methods },
    { hosts          = typedefs.hosts },
    { paths          = typedefs.paths },
    { headers = typedefs.headers {
      keys = typedefs.header_name {
        match_none = {
          {
            pattern = "^[Hh][Oo][Ss][Tt]$",
            err = "cannot contain 'host' header, which must be specified in the 'hosts' attribute",
          },
        },
      },
    } },
    { https_redirect_status_code = { type = "integer",
                                     one_of = { 426, 301, 302, 307, 308 },
                                     default = 426, required = true,
                                   }, },
    { regex_priority = { type = "integer", default = 0 }, },
    { strip_path     = { type = "boolean", required = true, default = true }, },
    { path_handling  = { type = "string", default = "v0", one_of = { "v0", "v1" }, }, },
    { preserve_host  = { type = "boolean", required = true, default = false }, },
    { request_buffering  = { type = "boolean", required = true, default = true }, },
    { response_buffering  = { type = "boolean", required = true, default = true }, },
    { snis = { type = "set",
               elements = typedefs.sni }, },
    { sources = typedefs.sources },
    { destinations = typedefs.destinations },
    { tags             = typedefs.tags },
    { service = { type = "foreign", reference = "services" }, },
  },

  entity_checks = {
    { conditional = { if_field = "protocols",
                      if_match = { elements = { type = "string", not_one_of = { "grpcs", "https", "tls", "tls_passthrough" }}},
                      then_field = "snis",
                      then_match = { len_eq = 0 },
                      then_err = "'snis' can only be set when 'protocols' is 'grpcs', 'https', 'tls' or 'tls_passthrough'",
                    }},
                  },
}
