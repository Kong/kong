local utils = require "kong.tools.utils"
local Errors = require "kong.dao.errors"

local function check_user(anonymous)
  if anonymous == "" or utils.is_valid_uuid(anonymous) then
    return true
  end
  
  return false, "the anonymous user must be empty or a valid uuid"
end

return {
  no_consumer = true,
  fields = {
    ldap_host = {required = true, type = "string"},
    ldap_port = {required = true, type = "number"},
    start_tls = {required = true, type = "boolean", default = false},
    ldaps = {required = true, type = "boolean", default = false},
    verify_ldap_host = {required = true, type = "boolean", default = false},
    base_dn = {required = true, type = "string"},
    attribute = {required = true, type = "string"},
    cache_ttl = {required = true, type = "number", default = 60},
    hide_credentials = {type = "boolean", default = false},
    timeout = {type = "number", default = 10000},
    keepalive = {type = "number", default = 60000},
    anonymous = {type = "string", default = "", func = check_user},
  },
  self_check = function(schema, plugin_t, dao, is_update)
    if plugin_t.ldaps and plugin_t.start_tls then
       return false, Errors.schema "LDAPS and StartTLS cannot be enabled simultaneously. You need to enable only one of the two."
    end
    return true
  end
}


