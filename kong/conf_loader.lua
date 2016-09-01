local kong_default_conf = require "kong.templates.kong_defaults"
local pl_stringio = require "pl.stringio"
local pl_stringx = require "pl.stringx"
local constants = require "kong.constants"
local pl_pretty = require "pl.pretty"
local pl_config = require "pl.config"
local pl_file = require "pl.file"
local pl_path = require "pl.path"
local tablex = require "pl.tablex"
local utils = require "kong.tools.utils"
local log = require "kong.cmd.utils.log"

local ipv4_port_pattern = "^(%d+)%.(%d+)%.(%d+)%.(%d+):(%d+)$"

local DEFAULT_PATHS = {
  "/etc/kong.conf",
  "/etc/kong/kong.conf"
}

local PREFIX_PATHS = {
  serf_pid = {"pids", "serf.pid"},
  serf_log = {"logs", "serf.log"},
  serf_event = {"serf", "serf_event.sh"},
  serf_node_id = {"serf", "serf.id"}
  ;
  nginx_pid = {"pids", "nginx.pid"},
  nginx_err_logs = {"logs", "error.log"},
  nginx_acc_logs = {"logs", "access.log"},
  nginx_conf = {"nginx.conf"},
  nginx_kong_conf = {"nginx-kong.conf"}
  ;
  kong_conf = {"kong.conf"}
  ;
  ssl_cert_default = {"ssl", "kong-default.crt"},
  ssl_cert_key_default = {"ssl", "kong-default.key"},
  ssl_cert_csr_default = {"ssl", "kong-default.csr"}
}

-- By default, all properties in the configuration are considered to
-- be strings/numbers, but if we want to forcefully infer their type, specify it
-- in this table.
-- Also holds "enums" which are lists of valid configuration values for some
-- settings.
-- See `typ_checks` for the validation function of each type.
--
-- Types:
-- `boolean`: can be "on"/"off"/"true"/"false", will be inferred to a boolean
-- `ngx_boolean`: can be "on"/"off", will be inferred to a string
-- `array`: a comma-separated list
local CONF_INFERENCES = {
  -- forced string inferences (or else are retrieved as numbers)
  proxy_listen = {typ = "string"},
  proxy_listen_ssl = {typ = "string"},
  admin_listen = {typ = "string"},
  cluster_listen = {typ = "string"},
  cluster_listen_rpc = {typ = "string"},
  cluster_advertise = {typ = "string"},
  nginx_worker_processes = {typ = "string"},

  database = {enum = {"postgres", "cassandra"}},
  pg_port = {typ = "number"},
  pg_ssl = {typ = "boolean"},
  pg_ssl_verify = {typ = "boolean"},

  cassandra_contact_points = {typ = "array"},
  cassandra_port = {typ = "number"},
  cassandra_repl_strategy = {enum = {"SimpleStrategy", "NetworkTopologyStrategy"}},
  cassandra_repl_factor = {typ = "number"},
  cassandra_data_centers = {typ = "array"},
  cassandra_consistency = {enum = {"ALL", "EACH_QUORUM", "QUORUM", "LOCAL_QUORUM", "ONE",
                                   "TWO", "THREE", "LOCAL_ONE"}}, -- no ANY: this is R/W
  cassandra_timeout = {typ = "number"},
  cassandra_ssl = {typ = "boolean"},
  cassandra_ssl_verify = {typ = "boolean"},

  cluster_profile = {enum = {"local", "lan", "wan"}},
  cluster_ttl_on_failure = {typ = "number"},

  dns_resolver = {typ = "array"},

  ssl = {typ = "boolean"},

  log_level = {enum = {"debug", "info", "notice", "warn",
                       "error", "crit", "alert", "emerg"}},
  custom_plugins = {typ = "array"},
  anonymous_reports = {typ = "boolean"},
  nginx_daemon = {typ = "ngx_boolean"},
  nginx_optimizations = {typ = "boolean"},

  lua_code_cache = {typ = "ngx_boolean"},
  lua_ssl_verify_depth = {typ = "number"}
}

-- List of settings whose values must not be printed when
-- using the CLI in debug mode (which prints all settings).
local CONF_SENSITIVE = {
  pg_password = true,
  cassandra_password = true,
  cluster_encrypt_key = true
}

local typ_checks = {
  array = function(v) return type(v) == "table" end,
  string = function(v) return type(v) == "string" end,
  number = function(v) return type(v) == "number" end,
  boolean = function(v) return type(v) == "boolean" end,
  ngx_boolean = function(v) return v == "on" or v == "off" end
}

-- Validate properties (type/enum/custom) and infer their type.
-- @param[type=table] conf The configuration table to treat.
local function check_and_infer(conf)
  local errors = {}

  for k, value in pairs(conf) do
    local v_schema = CONF_INFERENCES[k] or {}
    local typ = v_schema.typ

    if type(value) == "string" then
      value = string.gsub(value, "#.-$", "") -- remove trailing comment if any
      value = pl_stringx.strip(value)
    end

    -- transform {boolean} values ("on"/"off" aliasing to true/false)
    -- transform {ngx_boolean} values ("on"/"off" aliasing to on/off)
    -- transform {explicit string} values (number values converted to strings)
    -- transform {array} values (comma-separated strings)
    if typ == "boolean" then
      value = value == true or value == "on" or value == "true"
    elseif typ == "ngx_boolean" then
      value = (value == "on" or value == true) and "on" or "off"
    elseif typ == "string" then
      value = tostring(value) -- forced string inference
    elseif typ == "number" then
      value = tonumber(value) -- catch ENV variables (strings) that should be numbers
    elseif typ == "array" and type(value) == "string" then
      -- must check type because pl will already convert comma
      -- separated strings to tables (but not when the arr has
      -- only one element)
      value = setmetatable(pl_stringx.split(value, ","), nil) -- remove List mt
    end

    if value == "" then
      -- unset values are removed
      value = nil
    end

    typ = typ or "string"
    if value and not typ_checks[typ](value) then
      errors[#errors+1] = k.." is not a "..typ..": '"..tostring(value).."'"
    elseif v_schema.enum and not tablex.find(v_schema.enum, value) then
      errors[#errors+1] = k.." has an invalid value: '"..tostring(value)
                          .."' ("..table.concat(v_schema.enum, ", ")..")"
    end

    conf[k] = value
  end

  ---------------------
  -- custom validations
  ---------------------

  if conf.ssl then
    if conf.ssl_cert and not conf.ssl_cert_key then
      errors[#errors+1] = "ssl_cert_key must be specified"
    elseif conf.ssl_cert_key and not conf.ssl_cert then
      errors[#errors+1] = "ssl_cert must be specified"
    end

    if conf.ssl_cert and not pl_path.exists(conf.ssl_cert) then
      errors[#errors+1] = "ssl_cert: no such file at "..conf.ssl_cert
    end
    if conf.ssl_cert_key and not pl_path.exists(conf.ssl_cert_key) then
      errors[#errors+1] = "ssl_cert_key: no such file at "..conf.ssl_cert_key
    end
  end

  if conf.dns_resolver then
    for _, server in ipairs(conf.dns_resolver) do
      local dns = utils.normalize_ip(server)
      if (not dns) or (dns.type ~= "ipv4") then
        errors[#errors+1] = "dns_resolver must be a comma separated list in the form of IPv4 or IPv4:port"
        break -- one error is enough
      end
    end
  end

  if not conf.cluster_listen:match(ipv4_port_pattern) then
    errors[#errors+1] = "cluster_listen must be in the form of IPv4:port"
  end
  if not conf.cluster_listen_rpc:match(ipv4_port_pattern) then
    errors[#errors+1] = "cluster_listen_rpc must be in the form of IPv4:port"
  end
  if conf.cluster_advertise and not conf.cluster_advertise:match(ipv4_port_pattern) then
    errors[#errors+1] = "cluster_advertise must be in the form of IPv4:port"
  end
  if conf.cluster_ttl_on_failure < 60 then
    errors[#errors+1] = "cluster_ttl_on_failure must be at least 60 seconds"
  end
  if not conf.lua_package_cpath then
    conf.lua_package_cpath = ""
  end

  return #errors == 0, errors[1], errors
end

local function overrides(k, default_v, file_conf, arg_conf)
  local value -- definitive value for this property

  -- default values have lowest priority
  if file_conf and file_conf[k] == nil then
    -- PL will ignore empty strings, so we need a placeholer (NONE)
    value = default_v == "NONE" and "" or default_v
  else
    -- given conf values have middle priority
    value = file_conf[k]
  end

  -- environment variables have higher priority
  local env_name = "KONG_"..string.upper(k)
  local env = os.getenv(env_name)
  if env ~= nil then
    local to_print = env
    if CONF_SENSITIVE[k] then
      to_print = "******"
    end
    log.debug('%s ENV found with "%s"', env_name, to_print)
    value = env
  end

  -- arg_conf have highest priority
  if arg_conf and arg_conf[k] ~= nil then
    value = arg_conf[k]
  end

  return value, k
end

--- Load Kong configuration
-- The loaded configuration will have all properties from the default config
-- merged with the (optionally) specified config file, environment variables
-- and values specified in the `custom_conf` argument.
-- Values will then be validated and additional values (such as `proxy_port` or
-- `plugins`) will be appended to the final configuration table.
-- @param[type=string] path (optional) Path to a configuration file.
-- @param[type=table] custom_conf A key/value table with the highest precedence.
-- @treturn table A table holding a valid configuration.
local function load(path, custom_conf)
  ------------------------
  -- Default configuration
  ------------------------

  -- load defaults, they are our mandatory base
  local s = pl_stringio.open(kong_default_conf)
  local defaults, err = pl_config.read(s)
  s:close()
  if not defaults then return nil, "could not load default conf: "..err end

  ---------------------
  -- Configuration file
  ---------------------

  local from_file_conf = {}
  if path and not pl_path.exists(path) then
    -- file conf has been specified and must exist
    return nil, "no file at: "..path
  else
    -- try to look for a conf, but no big deal if none
    for _, default_path in ipairs(DEFAULT_PATHS) do
      if pl_path.exists(default_path) then
        path = default_path
        break
      end
      log.verbose("no config file found at %s", default_path)
    end
  end

  if not path then
    log.verbose("no config file, skipping loading")
  else
    local f, err = pl_file.read(path)
    if not f then return nil, err end

    log.verbose("reading config file at %s", path)
    local s = pl_stringio.open(f)
    from_file_conf, err = pl_config.read(s, {
      smart = false,
      list_delim = "_blank_" -- mandatory but we want to ignore it
    })
    s:close()
    if not from_file_conf then return nil, err end
  end

  -----------------------
  -- Merging & validation
  -----------------------

  -- merge default conf with file conf, ENV variables and arg conf (with precedence)
  local conf = tablex.pairmap(overrides, defaults, from_file_conf, custom_conf)

  -- validation
  local ok, err, errors = check_and_infer(conf)
  if not ok then return nil, err, errors end

  conf = tablex.merge(conf, defaults) -- intersection (remove extraneous properties)

  -- print alphabetically-sorted values
  do
    local conf_arr = {}
    for k, v in pairs(conf) do
      local to_print = v
      if CONF_SENSITIVE[k] then
        to_print = "******"
      end

      conf_arr[#conf_arr+1] = k.." = "..pl_pretty.write(to_print, "")
    end

    table.sort(conf_arr)

    for i = 1, #conf_arr do
      log.debug(conf_arr[i])
    end
  end

  -----------------------------
  -- Additional injected values
  -----------------------------

  -- merge plugins
  do
    local custom_plugins = {}
    for i = 1, #conf.custom_plugins do
      local plugin_name = conf.custom_plugins[i]
      custom_plugins[plugin_name] = true
    end
    conf.plugins = tablex.merge(constants.PLUGINS_AVAILABLE, custom_plugins, true)
    conf.custom_plugins = nil
    setmetatable(conf.plugins, nil) -- remove Map mt
  end

  -- extract ports/listen ips
  do
    local ip_port_pat = "(.+):([%d]+)$"
    local admin_ip, admin_port = string.match(conf.admin_listen, ip_port_pat)
    local proxy_ip, proxy_port = string.match(conf.proxy_listen, ip_port_pat)
    local proxy_ssl_ip, proxy_ssl_port = string.match(conf.proxy_listen_ssl, ip_port_pat)

    if not admin_port then return nil, "admin_listen must be of form 'address:port'"
    elseif not proxy_port then return nil, "proxy_listen must be of form 'address:port'"
    elseif not proxy_ssl_port then return nil, "proxy_listen_ssl must be of form 'address:port'" end
    conf.admin_ip = admin_ip
    conf.proxy_ip = proxy_ip
    conf.proxy_ssl_ip = proxy_ssl_ip
    conf.admin_port = tonumber(admin_port)
    conf.proxy_port = tonumber(proxy_port)
    conf.proxy_ssl_port = tonumber(proxy_ssl_port)
  end

  -- load absolute paths
  conf.prefix = pl_path.abspath(conf.prefix)

  if conf.ssl_cert and conf.ssl_cert_key then
    conf.ssl_cert = pl_path.abspath(conf.ssl_cert)
    conf.ssl_cert_key = pl_path.abspath(conf.ssl_cert_key)
  end

  -- attach prefix files paths
  for property, t_path in pairs(PREFIX_PATHS) do
    conf[property] = pl_path.join(conf.prefix, unpack(t_path))
  end

  log.verbose("prefix in use: %s", conf.prefix)

  return setmetatable(conf, nil) -- remove Map mt
end

return load
