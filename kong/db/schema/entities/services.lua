local typedefs = require "kong.db.schema.typedefs"
local Schema = require "kong.db.schema"
local url = require "socket.url"


local tostring = tostring
local tonumber = tonumber
local null = ngx.null


local nonzero_timeout = Schema.define {
  type = "integer",
  between = { 1, math.pow(2, 31) - 2 },
}


local default_protocol = "http"
local default_port = 80


return {
  name = "services",
  primary_key = { "id" },
  endpoint_key = "name",

  fields = {
    { id                 = typedefs.uuid, },
    { created_at         = typedefs.auto_timestamp_s },
    { updated_at         = typedefs.auto_timestamp_s },
    { name               = typedefs.name },
    { retries            = { type = "integer", default = 5, between = { 0, 32767 } }, },
    -- { tags             = { type = "array", array = { type = "string" } }, },
    { protocol           = typedefs.protocol { required = true, default = default_protocol } },
    { host               = typedefs.host { required = true } },
    { port               = typedefs.port { required = true, default = default_port }, },
    { path               = typedefs.path },
    { connect_timeout    = nonzero_timeout { default = 60000 }, },
    { write_timeout      = nonzero_timeout { default = 60000 }, },
    { read_timeout       = nonzero_timeout { default = 60000 }, },
    { tags               = typedefs.tags },
    { client_certificate = { type = "foreign", reference = "certificates" }, },
    -- { load_balancer = { type = "foreign", reference = "load_balancers" } },
  },

  entity_checks = {
    { conditional = { if_field = "protocol",
                      if_match = { one_of = { "tcp", "tls", "grpc", "grpcs" }},
                      then_field = "path",
                      then_match = { eq = null }}},
    { conditional = { if_field = "protocol",
                      if_match = { ne = "https" },
                      then_field = "client_certificate",
                      then_match = { eq = null }}},
  },

  shorthands = {
    { url = function(sugar_url)
              local parsed_url = url.parse(tostring(sugar_url))
              if not parsed_url then
                return
              end

              local port = tonumber(parsed_url.port)

              local prot
              if port == 80 then
                prot = "http"
              elseif port == 443 then
                prot = "https"
              end

              local protocol = parsed_url.scheme or prot or default_protocol

              return {
                protocol = protocol,
                host = parsed_url.host or null,
                port = port or
                       parsed_url.port or
                       (protocol == "http"  and 80)  or
                       (protocol == "https" and 443) or
                       default_port,
                path = parsed_url.path or null,
              }
            end },
  }
}
