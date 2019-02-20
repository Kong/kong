local typedefs = require "kong.db.schema.typedefs"


local function validate_host_with_wildcards(host)
  local no_wildcards = string.gsub(host, "%*", "abc")
  return typedefs.host.custom_validator(no_wildcards)
end


local function validate_path_with_regexes(path)

  local ok, err, err_code = typedefs.path.custom_validator(path)

  if ok or err_code ~= "rfc3986" then
    return ok, err, err_code
  end

  -- URI contains characters outside of the reserved list of RFC 3986:
  -- the value will be interpreted as a regex by the router; but is it a
  -- valid one? Let's dry-run it with the same options as our router.
  local _, _, err = ngx.re.find("", path, "aj")
  if err then
    return nil,
           string.format("invalid regex: '%s' (PCRE returned: %s)",
                         path, err)
  end

  return true
end


return {
  name         = "routes",
  primary_key  = { "id" },
  endpoint_key = "name",

  fields = {
    { id             = typedefs.uuid, },
    { created_at     = typedefs.auto_timestamp_s },
    { updated_at     = typedefs.auto_timestamp_s },
    { name           = typedefs.name },
    { protocols      = { type     = "set",
                         len_min  = 1,
                         required = true,
                         elements = typedefs.protocol,
                         default  = { "http", "https" }, -- TODO: different default depending on service's scheme
                       }, },
    { methods        = { type = "set",
                         elements = typedefs.http_method,
                       }, },
    { hosts          = { type = "array",
                         elements = {
                           type = "string",
                           match_all = {
                             {
                               pattern = "^[^*]*%*?[^*]*$",
                               err = "invalid wildcard: must have at most one wildcard",
                             },
                           },
                           match_any = {
                             patterns = { "^%*%.", "%.%*$", "^[^*]*$" },
                             err = "invalid wildcard: must be placed at leftmost or rightmost label",
                           },
                           custom_validator = validate_host_with_wildcards,
                         }
                       }, },
    { paths          = { type = "array",
                         elements = typedefs.path {
                           custom_validator = validate_path_with_regexes,
                           match_none = {
                             { pattern = "//",
                               err = "must not have empty segments"
                             },
                           },
                         }
                       }, },
    { https_redirect_status_code = { type = "integer",
                                     one_of = { 426, 301, 302, 307, 308 },
                                     default = 426, required = true,
                                   }, },
    { regex_priority = { type = "integer", default = 0 }, },
    { strip_path     = { type = "boolean", default = true }, },
    { preserve_host  = { type = "boolean", default = false }, },
    { snis = { type = "set",
               elements = typedefs.sni }, },
    { sources = { type = "set",
                  elements = {
                    type = "record",
                    fields = {
                      { ip = typedefs.ip_or_cidr },
                      { port = typedefs.port },
                    },
                    entity_checks = {
                      { at_least_one_of = { "ip", "port" } }
                    },
                  },
                }, },
    { destinations = { type = "set",
                       elements = {
                         type = "record",
                         fields = {
                           { ip = typedefs.ip_or_cidr },
                           { port = typedefs.port },
                         },
                         entity_checks = {
                           { at_least_one_of = { "ip", "port" } }
                         },
                       },
                     }, },
    { tags             = typedefs.tags },
    { service = { type = "foreign", reference = "services" }, },
  },

  entity_checks = {
    { conditional_at_least_one_of = { if_field = "protocols",
                                      if_match = { elements = { type = "string", one_of = { "http", "https" }}},
                                      then_at_least_one_of = { "methods", "hosts", "paths" },
                                      then_err = "must set one of %s when 'protocols' is 'http' or 'https'",
                                      else_match = { elements = { type = "string", one_of = { "tcp", "tls" }}},
                                      else_then_at_least_one_of = { "sources", "destinations", "snis" },
                                      else_then_err = "must set one of %s when 'protocols' is 'tcp' or 'tls'",
                                    }},

    { conditional = { if_field = "protocols",
                      if_match = { elements = { type = "string", one_of = { "tcp", "tls" }}},
                      then_field = "hosts",
                      then_match = { len_eq = 0 },
                      then_err = "cannot set 'hosts' when 'protocols' is 'tcp' or 'tls'",
                    }},
    { conditional = { if_field = "protocols",
                      if_match = { elements = { type = "string", one_of = { "tcp", "tls" }}},
                      then_field = "paths",
                      then_match = { len_eq = 0 },
                      then_err = "cannot set 'paths' when 'protocols' is 'tcp' or 'tls'",
                    }},
    { conditional = { if_field = "protocols",
                      if_match = { elements = { type = "string", one_of = { "tcp", "tls" }}},
                      then_field = "methods",
                      then_match = { len_eq = 0 },
                      then_err = "cannot set 'methods' when 'protocols' is 'tcp' or 'tls'",
                    }},

    { conditional = { if_field = "protocols",
                      if_match = { elements = { type = "string", one_of = { "http", "https" }}},
                      then_field = "snis",
                      then_match = { len_eq = 0 },
                      then_err = "cannot set 'snis' when 'protocols' is 'http' or 'https'",
                    }},
    { conditional = { if_field = "protocols",
                      if_match = { elements = { type = "string", one_of = { "http", "https" }}},
                      then_field = "destinations",
                      then_match = { len_eq = 0 },
                      then_err = "cannot set 'destinations' when 'protocols' is 'http' or 'https'",
                    }},
    { conditional = { if_field = "protocols",
                      if_match = { elements = { type = "string", one_of = { "http", "https" }}},
                      then_field = "sources",
                      then_match = { len_eq = 0 },
                      then_err = "cannot set 'sources' when 'protocols' is 'http' or 'https'",
                    }},
  },
}
