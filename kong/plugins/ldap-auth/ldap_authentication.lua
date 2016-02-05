local ldap = require "lua_ldap"

local _M = {}

local function bind_authenticate(given_username, given_password, conf)
  local binding, error = ldap.open_simple(
    {
      uri = conf.ldap_protocol.."://"..conf.ldap_host..":"..conf.ldap_port,
      who = conf.attribute.."="..given_username..","..conf.base_dn,
      password = given_password,
      starttls = conf.start_tls,
      cacertfile = conf.cacert_path,
      cacertdir = conf.cacertdir_path,
      certfile = conf.cert_path,
      keyfile = conf.key_path
    })
 
  if binding ~= nil then
    return true;
  end
  return false, error
end

function _M.authenticate(given_username, given_password, conf)
  return bind_authenticate(given_username, given_password, conf)
end

return _M
