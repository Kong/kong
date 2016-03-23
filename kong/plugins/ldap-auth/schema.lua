local DaoError = require "kong.dao.error"
local constants = require "kong.constants"

return {
fields = {
    ldap_protocol = {required = true, type = "string", enum = {"ldap", "ldaps"}},
    ldap_host = {required = true, type = "string"},
    ldap_port = {required = true, type = "number"},
    start_tls = {required = true, type = "boolean", default = false},
    cert_path = {required = false, type = "string"},
    key_path = {required = false, type = "string"},
    cacert_path = {required = false, type = "string"},
    cacertdir_path = {required = false, type = "string"},
    base_dn = {required = true, type = "string"},
    attribute = {required = true, type = "string"},
    cache_ttl = {required = true, type = "number", default = 60},
    hide_credentials = {type = "boolean", default = false}
  },
  self_check = function(schema, plugin_t, dao, is_update)
    if plugin_t["ldap_protocol"] == "ldaps" and plugin_t["start_tls"] then
      return false, DaoError("You cannot set start_tls to 'true' when protocol is selected as 'ldaps'", constants.DATABASE_ERROR_TYPES.SCHEMA)
    end
    
    return true
  end
}
