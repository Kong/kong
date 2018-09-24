local cjson        = require "cjson.safe"
local pl_path      = require "pl.path"
local portal_utils = require "kong.portal.utils"
local pl_stringx   = require "pl.stringx"


-- @param value The options string to check for flags (whitespace separated)
-- @param flags List of boolean flags to check for.
-- @returns 1) remainder string after all flags removed, 2) table with flag
-- booleans, 3) sanitized flags string
local function parse_option_flags(value, flags)
  assert(type(value) == "string")

  value = " " .. value .. " "

  local sanitized = ""
  local result = {}

  for _, flag in ipairs(flags) do
    local count
    local patt = "%s" .. flag .. "%s"

    value, count = value:gsub(patt, " ")

    if count > 0 then
      result[flag] = true
      sanitized = sanitized .. " " .. flag

    else
      result[flag] = false
    end
  end

  return pl_stringx.strip(value), result, pl_stringx.strip(sanitized)
end


local function validate_admin_gui_authentication(conf, errors)
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
end


local function validate_admin_gui_ssl(conf, errors)
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
end


local function validate_email(email, key, errors)
  local ok, err = portal_utils.validate_email(email)
  if not ok then
    errors[#errors+1] = key .. " is invalid: " .. err
  end
end


local function validate_portal_smtp_config(conf, errors)
  local portal_token_exp = conf.portal_token_exp
  if type(portal_token_exp) ~= "number" or portal_token_exp < 1 then
    errors[#errors+1] = "portal_token_exp must be a positive number"
  end

  local smtp_admin_emails = conf.smtp_admin_emails
  if conf.smtp_mock then
    if next(smtp_admin_emails) == nil then
      conf.smtp_admin_emails = {"admin@example.com"}
    end
    return
  end

  if not conf.portal_gui_url or conf.portal_gui_url == "" then
    errors[#errors+1] = "portal_gui_url is required for portal"
  end

  if not conf.admin_gui_url or conf.admin_gui_url == "" then
    errors[#errors+1] = "admin_gui_url is required for portal"
  end

  validate_email(conf.portal_emails_from, "portal_emails_from", errors)
  validate_email(conf.portal_emails_reply_to, "portal_emails_reply_to", errors)
  validate_email(conf.portal_emails_from, "portal_emails_from", errors)

  if next(smtp_admin_emails) == nil then
    errors[#errors+1] = "smtp_admin_emails is required for portal"
  else
    for _, email in ipairs(smtp_admin_emails) do
      validate_email(email, "smtp_admin_emails", errors)
    end
  end
end


local function validate_vitals_prometheus(conf, errors)
  if conf.vitals_strategy == "prometheus" then
    if not conf.vitals_statsd_address or not conf.vitals_prometheus_address then
      errors[#errors+1] = "vitals_statsd_address and vitals_prometheus_address must be defined " .. 
      "when vitals_strategy is set to \"prometheus\""
    end
  elseif conf.vitals_strategy ~= "database" then
    errors[#errors+1] = "vitals_strategy must be either \"database\" or \"prometheus\""
  end

  do
    -- validate the presence of form of host and port
    -- we cannot inject values into conf here as the table will be intersected
    -- with the defaults table following this call
    if conf.vitals_prometheus_address then
      local host, port
      host, port = conf.vitals_prometheus_address:match("(.+):([%d]+)$")
      port = tonumber(port)
      if not host or not port then
        errors[#errors+1] = "vitals_prometheus_address must be of form: <ip>:<port>"
      end
    end
  end

  do
    if conf.vitals_statsd_address then
      local host, port
      local remainder, _, _ = parse_option_flags(conf.vitals_statsd_address, { "udp", "tcp" })
      if remainder then
        host, port = remainder:match("(.+):([%d]+)$")
        port = tonumber(port)
        if not host or not port then
          host = remainder:match("(unix:/.+)$")
        end
      end
      if not host then
        errors[#errors+1] = "vitals_statsd_address must be of form: <ip>:<port> [udp|tcp]"
      end
    end
  end

  if conf.vitals_statsd_udp_packet_size <= 0 or conf.vitals_statsd_udp_packet_size > 65507 then
    errors[#errors+1] = "vitals_statsd_udp_packet_size must be an positive integer and no larger than 65507"
  end

  if conf.vitals_prometheus_scrape_interval <= 0 then
    errors[#errors+1] = "vitals_prometheus_scrape_interval must be an positive integer"
  end

  return errors
end


local function validate(conf, errors)
  validate_admin_gui_authentication(conf, errors)
  validate_admin_gui_ssl(conf, errors)

  if conf.portal then
    validate_portal_smtp_config(conf, errors)
  end

  validate_vitals_prometheus(conf, errors)
end


return {
  validate = validate,
  -- only exposed for unit testing :-(
  validate_admin_gui_authentication = validate_admin_gui_authentication,
  validate_admin_gui_ssl = validate_admin_gui_ssl,
  validate_portal_smtp_config = validate_portal_smtp_config,
}
