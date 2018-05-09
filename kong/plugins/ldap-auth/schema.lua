local utils = require "kong.tools.utils"

local function check_user(anonymous)
  if anonymous == "" or utils.is_valid_uuid(anonymous) then
    return true
  end

  return false, "the anonymous user must be empty or a valid uuid"
end

-- If you add more configuration parameters, be sure to check if it needs to be added to cache key

return {
  no_consumer = true,
  fields = {
    ldap_host = {required = true, type = "string"},                          -- used for cache key
    ldap_port = {required = true, type = "number"},                          -- used for cache key
    start_tls = {required = true, type = "boolean", default = false},
    verify_ldap_host = {required = true, type = "boolean", default = false},
    base_dn = {required = true, type = "string"},                            -- used for cache key
    attribute = {required = true, type = "string"},                          -- used for cache key
    cache_ttl = {required = true, type = "number", default = 60},            -- used for cache key
    hide_credentials = {type = "boolean", default = false},
    timeout = {type = "number", default = 10000},
    keepalive = {type = "number", default = 60000},
    anonymous = {type = "string", default = "", func = check_user},
    header_type = {type = "string", default = "ldap"},
  }
}
