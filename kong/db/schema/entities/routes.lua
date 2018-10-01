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
                         default  = { "http", "https" },
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
    { regex_priority = { type = "integer", default = 0 }, },
    { strip_path     = { type = "boolean", default = true }, },
    { preserve_host  = { type = "boolean", default = false }, },
    { service        = { type = "foreign", reference = "services", required = true }, },
  },

  entity_checks = {
    { at_least_one_of = {"methods", "hosts", "paths"} },
  },
}
