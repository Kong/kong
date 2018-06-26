local cjson = require "cjson.safe"
local tablex = require "pl.tablex"
local pl_path = require "pl.path"


local function validate_admin_gui_authentication(conf)
  local errors = {}

-- TODO: reinstate validation after testing all auth types
--  if conf.admin_gui_auth then
--    if conf.admin_gui_auth ~= "key-auth" and
--      conf.admin_gui_auth ~= "basic-auth" and
--      conf.admin_gui_auth ~= "ldap-auth-advanced" then
--      errors[#errors+1] = "admin_gui_auth must be 'key-auth', 'basic-auth', " ..
--        "'ldap-auth-advanced' or not set"
--    end
--
--  end

  if conf.admin_gui_auth_conf and conf.admin_gui_auth_conf ~= "" then
    if not conf.admin_gui_auth or conf.admin_gui_auth == "" then
      errors[#errors+1] = "admin_gui_auth_conf is set with no admin_gui_auth"
    end

    local auth_config, err = cjson.decode(tostring(conf.admin_gui_auth_conf))
    if err then
      errors[#errors+1] = "admin_gui_auth_conf must be valid json or not set: "
        .. err .. " - " .. conf.admin_gui_auth_conf
    else
      conf.admin_gui_auth_conf = auth_config

      -- used for writing back to prefix/.kong_env
      setmetatable(conf.admin_gui_auth_conf, {
        __tostring = function (v)
          return assert(cjson.encode(v))
        end
      })
    end
  end

  return errors
end


local function validate_admin_gui_ssl(conf)
  local errors = {}

  if (table.concat(conf.admin_gui_listen, ",") .. " "):find("%sssl[%s,]") then
    if conf.admin_gui_ssl_cert and not conf.admin_gui_ssl_cert_key then
      errors[#errors+1] = "admin_gui_ssl_cert_key must be specified"
    elseif conf.admin_gui_ssl_cert_key and not conf.admin_gui_ssl_cert then
      errors[#errors+1] = "admin_gui_ssl_cert must be specified"
    end

    if conf.admin_gui_ssl_cert and not pl_path.exists(conf.admin_gui_ssl_cert) then
      errors[#errors+1] = "admin_gui_ssl_cert: no such file at " .. conf.admin_gui_ssl_cert
    end
    if conf.admin_gui_ssl_cert_key and not pl_path.exists(conf.admin_gui_ssl_cert_key) then
      errors[#errors+1] = "admin_gui_ssl_cert_key: no such file at " .. conf.admin_gui_ssl_cert_key
    end
  end

  return errors
end


local function validate(conf)
  local errors = {}

  tablex.merge(errors, validate_admin_gui_authentication(conf))

  tablex.merge(errors, validate_admin_gui_ssl(conf))

  return errors
end


return {
  validate = validate,
  -- only exposed for unit testing :-(
  validate_admin_gui_authentication = validate_admin_gui_authentication,
  validate_admin_gui_ssl = validate_admin_gui_ssl,
}
