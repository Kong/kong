local cjson        = require "cjson.safe"
local pl_path      = require "pl.path"
local pl_stringx   = require "pl.stringx"
local enterprise_utils = require "kong.enterprise_edition.utils"
local re_match = ngx.re.match


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
  if conf.admin_gui_auth then
    if conf.admin_gui_auth ~= "key-auth" and
       conf.admin_gui_auth ~= "basic-auth" and
       conf.admin_gui_auth ~= "ldap-auth-advanced" and
        conf.admin_gui_auth ~= "openid-connect" then
      errors[#errors+1] = "admin_gui_auth must be 'key-auth', 'basic-auth', " ..
        "'ldap-auth-advanced', 'openid-connect' or not set"
    end

    if not conf.enforce_rbac or conf.enforce_rbac == 'off' then
      errors[#errors+1] = "enforce_rbac must be enabled when " ..
          "admin_gui_auth is enabled"
    end
  end

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


local function validate_admin_gui_session(conf, errors)
  if conf.admin_gui_session_conf then
    if not conf.admin_gui_auth or conf.admin_gui_auth == "" then
      errors[#errors+1] = "admin_gui_session_conf is set with no admin_gui_auth"
    end

    local session_config, err = cjson.decode(tostring(conf.admin_gui_session_conf))
    if err then
      errors[#errors+1] = "admin_gui_session_conf must be valid json or not set: "
        .. err .. " - " .. conf.admin_gui_session_conf
    else
      conf.admin_gui_session_conf = session_config

      -- used for writing back to prefix/.kong_env
      setmetatable(conf.admin_gui_session_conf, {
        __tostring = function (v)
          return assert(cjson.encode(v))
        end
      })
    end
  end
end


-- Modified from kong.plugins.cors.schema check_regex func
-- TODO: use `is_regex` validator from core when 1.0 is merged
local function validate_portal_cors_origins(conf, errors)
  for _, origin in ipairs(conf.portal_cors_origins) do
    if origin ~= "*" then
      local _, err = re_match("any string", origin)
      if err then
        errors[#errors+1] = "portal_cors_origins: '" .. origin .. "' is not a valid regex"
      end
    end
  end
end


local function validate_portal_session(conf, errors)
  if conf.portal_session_conf then
    local session_config, err = cjson.decode(tostring(conf.portal_session_conf))
    if err then
      errors[#errors+1] = "portal_session_conf must be valid json or not set: "
        .. err .. " - " .. conf.portal_session_conf
    else
      if type(session_config.secret) ~= "string" then
        errors[#errors+1] = "portal_session_conf 'secret' must be type 'string'"
      end

      conf.portal_session_conf = session_config
       -- used for writing back to prefix/.kong_env
      setmetatable(conf.portal_session_conf, {
        __tostring = function (v)
          return assert(cjson.encode(v))
        end
      })
    end
  elseif conf.portal_auth and
         conf.portal_auth ~= "" and
         conf.portal_auth ~= "openid-connect" then
    -- portal_session_conf is required for portal_auth other than openid-connect
    errors[#errors+1] = "portal_session_conf is required when portal_auth is set to " .. conf.portal_auth
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
  local ok, err = enterprise_utils.validate_email(email)
  if not ok then
    errors[#errors+1] = key .. " is invalid: " .. err
  end
end

local function validate_smtp_config(conf, errors)
  if conf.smtp_auth_type ~= nil then
    if conf.smtp_auth_type ~= "plain" and conf.smtp_auth_type ~= "login" then
      errors[#errors+1] = "smtp_auth_type must be 'plain', 'login', or nil"
    end

    if conf.smtp_username == nil or conf.smtp_username == "" then
      errors[#errors+1] = "smtp_username must be set when using smtp_auth_type"
    end

    if conf.smtp_password == nil or conf.smtp_password == "" then
      errors[#errors+1] = "smtp_password must be set when using smtp_auth_type"
    end
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


local function validate_vitals_tsdb(conf, errors)
  if conf.vitals_strategy == "prometheus" or
     conf.vitals_strategy == "influxdb" then

    if not conf.vitals_tsdb_address then
      errors[#errors + 1] = "vitals_tsdb_address must be defined when " ..
        "vitals_strategy = \"prometheus\" or \"influxdb\""
    end

    if not conf.vitals_statsd_address and conf.vitals_strategy == "prometheus"
      then

      errors[#errors+1] = "vitals_statsd_address must be defined " ..
        "when vitals_strategy is set to \"prometheus\""
    end

  elseif conf.vitals_strategy ~= "database" then
    errors[#errors+1] = 'vitals_strategy must be one of ' ..
      '"database", "prometheus", or "influxdb"'
  end

  do
    -- validate the presence of form of host and port
    -- we cannot inject values into conf here as the table will be intersected
    -- with the defaults table following this call
    if conf.vitals_tsdb_address then
      local host, port
      host, port = conf.vitals_tsdb_address:match("(.+):([%d]+)$")
      port = tonumber(port)
      if not host or not port then
        errors[#errors+1] = "vitals_tsdb_address must be of form: <ip>:<port>"
      else
        conf.vitals_tsdb_host = host
        conf.vitals_tsdb_port = port
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


local function add_ee_required_plugins(conf)
  local seen_plugins = {}
  for _, plugin in ipairs(conf.plugins) do
    -- If using bundled plugins, we can eject early
    if plugin == "bundled" then
      return
    end

    seen_plugins[plugin] = true
  end

  -- Required by both admin api and portal
  local required_plugins = { "cors", "session" }

  -- Required for manager
  if conf.admin_gui_auth and conf.admin_gui_auth ~= "" then
    required_plugins[#required_plugins + 1] = conf.admin_gui_auth
  end

  -- Required for portal - all options are needed so that workspace portals
  -- can select them independently from the default conf value
  if conf.portal then
    required_plugins[#required_plugins + 1] = "basic-auth"
    required_plugins[#required_plugins + 1] = "key-auth"
  end

  for _, required_plugin in ipairs(required_plugins) do
    if not seen_plugins[required_plugin] then
      conf.plugins[#conf.plugins+1] = required_plugin
    end
  end
end

local function validate_tracing(conf, errors)
  if conf.tracing and not conf.tracing_write_endpoint then
    errors[#errors + 1] = "'tracing_write_endpoint' must be defined when " ..
      "'tracing' is enabled"
  end
end


local function validate_route_path_pattern(conf, errors)
  local pattern = conf.enforce_route_path_pattern
  if conf.route_validation_strategy == "path" then
    if not pattern then
      errors[#errors + 1] = "'enforce_route_path_pattern'is required when" ..
        "'route_validation_strategy' is set to 'path'"
      return
    end

    if not string.match(pattern, "^/[%w%.%-%_~%/%%%$%(%)%*]*$") then
      errors[#errors + 1] = "invalid path pattern: '" .. pattern
    end
  end
end


local function validate(conf, errors)
  validate_admin_gui_authentication(conf, errors)
  validate_admin_gui_ssl(conf, errors)
  validate_admin_gui_session(conf, errors)

  if not conf.smtp_mock then
    validate_smtp_config(conf, errors)
  end

  if conf.portal then
    validate_portal_smtp_config(conf, errors)
    validate_portal_session(conf, errors)

    local portal_gui_host = conf.portal_gui_host
    if not portal_gui_host or portal_gui_host == "" then
      errors[#errors+1] = "portal_gui_host is required for portal"
    end

    local portal_gui_protocol = conf.portal_gui_protocol
    if not portal_gui_protocol or portal_gui_protocol == "" then
      errors[#errors+1] = "portal_gui_protocol is required for portal"
    end

    validate_portal_cors_origins(conf, errors)
  end

  validate_vitals_tsdb(conf, errors)
  add_ee_required_plugins(conf)
  validate_tracing(conf, errors)
  validate_route_path_pattern(conf, errors)
end


return {
  validate = validate,
  -- only exposed for unit testing :-(
  validate_admin_gui_authentication = validate_admin_gui_authentication,
  validate_admin_gui_ssl = validate_admin_gui_ssl,
  validate_smtp_config = validate_smtp_config,
  validate_portal_smtp_config = validate_portal_smtp_config,
  validate_portal_cors_origins = validate_portal_cors_origins,
  validate_tracing = validate_tracing,
  validate_route_path_pattern = validate_route_path_pattern,
}
