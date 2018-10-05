local kong_default_conf = require "kong.templates.kong_defaults"
local pl_stringio = require "pl.stringio"
local pl_stringx = require "pl.stringx"
local constants = require "kong.constants"
local pl_pretty = require "pl.pretty"
local pl_config = require "pl.config"
local ciphers = require "kong.tools.ciphers"
local pl_file = require "pl.file"
local pl_path = require "pl.path"
local tablex = require "pl.tablex"
local utils = require "kong.tools.utils"
local log = require "kong.cmd.utils.log"
local env = require "kong.cmd.utils.env"
local ip = require "kong.tools.ip"


local fmt = string.format
local concat = table.concat


local DEFAULT_PATHS = {
  "/etc/kong/kong.conf",
  "/etc/kong.conf",
}

local secret_path = "/etc/kong/secrets"

local HEADERS = constants.HEADERS
local HEADER_KEY_TO_NAME = {
  ["server_tokens"] = "server_tokens",
  ["latency_tokens"] = "latency_tokens",
  [string.lower(HEADERS.VIA)] = HEADERS.VIA,
  [string.lower(HEADERS.SERVER)] = HEADERS.SERVER,
  [string.lower(HEADERS.PROXY_LATENCY)] = HEADERS.PROXY_LATENCY,
  [string.lower(HEADERS.UPSTREAM_LATENCY)] = HEADERS.UPSTREAM_LATENCY,
  [string.lower(HEADERS.UPSTREAM_STATUS)] = HEADERS.UPSTREAM_STATUS,
}


local DYNAMIC_KEY_PREFIXES = {
  ["nginx_http_directives"] = "nginx_http_",
  ["nginx_proxy_directives"] = "nginx_proxy_",
  ["nginx_admin_directives"] = "nginx_admin_",
}


local PREFIX_PATHS = {
  nginx_pid = {"pids", "nginx.pid"},
  nginx_err_logs = {"logs", "error.log"},
  nginx_acc_logs = {"logs", "access.log"},
  admin_acc_logs = {"logs", "admin_access.log"},
  nginx_conf = {"nginx.conf"},
  nginx_kong_conf = {"nginx-kong.conf"},

  kong_env = {".kong_env"},

  ssl_cert_default = {"ssl", "kong-default.crt"},
  ssl_cert_key_default = {"ssl", "kong-default.key"},
  ssl_cert_csr_default = {"ssl", "kong-default.csr"},

  client_ssl_cert_default = {"ssl", "kong-default.crt"},
  client_ssl_cert_key_default = {"ssl", "kong-default.key"},
  client_ssl_cert_csr_default = {"ssl", "kong-default.csr"},

  admin_ssl_cert_default = {"ssl", "admin-kong-default.crt"},
  admin_ssl_cert_key_default = {"ssl", "admin-kong-default.key"},
  admin_ssl_cert_csr_default = {"ssl", "admin-kong-default.csr"},
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
  proxy_listen = { typ = "array" },
  admin_listen = { typ = "array" },
  db_update_frequency = {  typ = "number"  },
  db_update_propagation = {  typ = "number"  },
  db_cache_ttl = {  typ = "number"  },
  db_resurrect_ttl = {  typ = "number"  },
  nginx_user = { typ = "string" },
  nginx_worker_processes = { typ = "string" },
  upstream_keepalive = { typ = "number" },
  headers = { typ = "array" },
  trusted_ips = { typ = "array" },
  real_ip_header = { typ = "string" },
  real_ip_recursive = { typ = "ngx_boolean" },
  client_max_body_size = { typ = "string" },
  client_body_buffer_size = { typ = "string" },
  error_default_type = { enum = {
                           "application/json",
                           "application/xml",
                           "text/html",
                           "text/plain",
                         }
                       },

  database = { enum = { "postgres", "cassandra" }  },
  pg_port = { typ = "number" },
  pg_password = { typ = "string" },
  pg_ssl = { typ = "boolean" },
  pg_ssl_verify = { typ = "boolean" },

  cassandra_contact_points = { typ = "array" },
  cassandra_port = { typ = "number" },
  cassandra_password = { typ = "string" },
  cassandra_timeout = { typ = "number" },
  cassandra_ssl = { typ = "boolean" },
  cassandra_ssl_verify = { typ = "boolean" },
  cassandra_consistency = { enum = {
                              "ALL",
                              "EACH_QUORUM",
                              "QUORUM",
                              "LOCAL_QUORUM",
                              "ONE",
                              "TWO",
                              "THREE",
                              "LOCAL_ONE",
                            }
                          },
  cassandra_lb_policy = { enum = {
                            "RoundRobin",
                            "RequestRoundRobin",
                            "DCAwareRoundRobin",
                            "RequestDCAwareRoundRobin",
                          }
                        },
  cassandra_local_datacenter = { typ = "string" },
  cassandra_repl_strategy = { enum = {
                                "SimpleStrategy",
                                "NetworkTopologyStrategy",
                              }
                            },
  cassandra_repl_factor = { typ = "number" },
  cassandra_data_centers = { typ = "array" },
  cassandra_schema_consensus_timeout = { typ = "number" },

  dns_resolver = { typ = "array" },
  dns_hostsfile = { typ = "string" },
  dns_order = { typ = "array" },
  dns_valid_ttl = { typ = "number" },
  dns_stale_ttl = { typ = "number" },
  dns_not_found_ttl = { typ = "number" },
  dns_error_ttl = { typ = "number" },
  dns_no_sync = { typ = "boolean" },

  client_ssl = { typ = "boolean" },

  proxy_access_log = { typ = "string" },
  proxy_error_log = { typ = "string" },
  admin_access_log = { typ = "string" },
  admin_error_log = { typ = "string" },
  log_level = { enum = {
                  "debug",
                  "info",
                  "notice",
                  "warn",
                  "error",
                  "crit",
                  "alert",
                  "emerg",
                }
              },
  plugins = { typ = "array" },
  custom_plugins = { typ = "array" },
  anonymous_reports = { typ = "boolean" },
  nginx_daemon = { typ = "ngx_boolean" },
  nginx_optimizations = { typ = "boolean" },

  lua_ssl_verify_depth = { typ = "number" },
  lua_socket_pool_size = { typ = "number" },
}


-- List of settings whose values must not be printed when
-- using the CLI in debug mode (which prints all settings).
local CONF_SENSITIVE_PLACEHOLDER = "******"
local CONF_SENSITIVE = {
  pg_password = true,
  cassandra_password = true,
}


local typ_checks = {
  array = function(v) return type(v) == "table" end,
  string = function(v) return type(v) == "string" end,
  number = function(v) return type(v) == "number" end,
  boolean = function(v) return type(v) == "boolean" end,
  ngx_boolean = function(v) return v == "on" or v == "off" end,
}


-- This meta table will prevent the parsed table to be passed on in the
-- intermediate Kong config file in the prefix directory.
-- We thus avoid 'table: 0x41c3fa58' from appearing into the prefix
-- hidden configuration file.
-- This is only to be applied to values that are injected into the
-- configuration object, and not configuration properties themselves,
-- otherwise we would prevent such properties from being specifiable
-- via environment variables.
local _nop_tostring_mt = {
  __tostring = function() return "" end,
}


-- Validate properties (type/enum/custom) and infer their type.
-- @param[type=table] conf The configuration table to treat.
local function check_and_infer(conf)
  local errors = {}

  for k, value in pairs(conf) do
    local v_schema = CONF_INFERENCES[k] or {}
    local typ = v_schema.typ

    if type(value) == "string" then
      -- remove trailing comment, if any
      -- and remove escape chars from octothorpes
      value = string.gsub(value, "[^\\]#.-$", "")
      value = string.gsub(value, "\\#", "#")

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
      value = tonumber(value) -- catch ENV variables (strings) that are numbers

    elseif typ == "array" and type(value) == "string" then
      -- must check type because pl will already convert comma
      -- separated strings to tables (but not when the arr has
      -- only one element)
      value = setmetatable(pl_stringx.split(value, ","), nil) -- remove List mt

      for i = 1, #value do
        value[i] = pl_stringx.strip(value[i])
      end
    end

    if value == "" then
      -- unset values are removed
      value = nil
    end

    typ = typ or "string"

    if value and not typ_checks[typ](value) then
      errors[#errors + 1] = fmt("%s is not a %s: '%s'", k, typ,
                                tostring(value))

    elseif v_schema.enum and not tablex.find(v_schema.enum, value) then
      errors[#errors + 1] = fmt("%s has an invalid value: '%s' (%s)", k,
                              tostring(value), concat(v_schema.enum, ", "))

    end

    conf[k] = value
  end

  ---------------------
  -- custom validations
  ---------------------

  if conf.database == "cassandra" then
    if conf.cassandra_lb_policy == "DCAwareRoundRobin"
       and not conf.cassandra_local_datacenter
    then
      errors[#errors + 1] = "must specify 'cassandra_local_datacenter' when " ..
                          "DCAwareRoundRobin policy is in use"
    end

    for _, contact_point in ipairs(conf.cassandra_contact_points) do
      local endpoint, err = utils.normalize_ip(contact_point)
      if not endpoint then
        errors[#errors + 1] = fmt("bad cassandra contact point '%s': %s",
                                  contact_point, err)

      elseif endpoint.port then
        errors[#errors + 1] = fmt("bad cassandra contact point '%s': %s",
                                  contact_point,
                                  "port must be specified in cassandra_port")
      end
    end

    -- cache settings check

    if conf.db_update_propagation == 0 then
      log.warn("You are using Cassandra but your 'db_update_propagation' " ..
               "setting is set to '0' (default). Due to the distributed "  ..
               "nature of Cassandra, you should increase this value.")
    end
  end

  if (concat(conf.proxy_listen, ",") .. " "):find("%sssl[%s,]") then
    if conf.ssl_cert and not conf.ssl_cert_key then
      errors[#errors + 1] = "ssl_cert_key must be specified"

    elseif conf.ssl_cert_key and not conf.ssl_cert then
      errors[#errors + 1] = "ssl_cert must be specified"
    end

    if conf.ssl_cert and not pl_path.exists(conf.ssl_cert) then
      errors[#errors + 1] = "ssl_cert: no such file at " .. conf.ssl_cert
    end

    if conf.ssl_cert_key and not pl_path.exists(conf.ssl_cert_key) then
      errors[#errors + 1] = "ssl_cert_key: no such file at " .. conf.ssl_cert_key
    end
  end

  if conf.client_ssl then
    if conf.client_ssl_cert and not conf.client_ssl_cert_key then
      errors[#errors + 1] = "client_ssl_cert_key must be specified"

    elseif conf.client_ssl_cert_key and not conf.client_ssl_cert then
      errors[#errors + 1] = "client_ssl_cert must be specified"
    end

    if conf.client_ssl_cert and not pl_path.exists(conf.client_ssl_cert) then
      errors[#errors + 1] = "client_ssl_cert: no such file at " ..
                          conf.client_ssl_cert
    end

    if conf.client_ssl_cert_key and not pl_path.exists(conf.client_ssl_cert_key) then
      errors[#errors + 1] = "client_ssl_cert_key: no such file at " ..
                          conf.client_ssl_cert_key
    end
  end

  if (concat(conf.admin_listen, ",") .. " "):find("%sssl[%s,]") then
    if conf.admin_ssl_cert and not conf.admin_ssl_cert_key then
      errors[#errors + 1] = "admin_ssl_cert_key must be specified"

    elseif conf.admin_ssl_cert_key and not conf.admin_ssl_cert then
      errors[#errors + 1] = "admin_ssl_cert must be specified"
    end

    if conf.admin_ssl_cert and not pl_path.exists(conf.admin_ssl_cert) then
      errors[#errors + 1] = "admin_ssl_cert: no such file at " ..
                          conf.admin_ssl_cert
    end

    if conf.admin_ssl_cert_key and not pl_path.exists(conf.admin_ssl_cert_key) then
      errors[#errors + 1] = "admin_ssl_cert_key: no such file at " ..
                          conf.admin_ssl_cert_key
    end
  end

  if conf.ssl_cipher_suite ~= "custom" then
    local pok, perr = pcall(function()
      conf.ssl_ciphers = ciphers(conf.ssl_cipher_suite)
    end)
    if not pok then
      errors[#errors + 1] = perr
    end
  end

  if conf.headers then
    for _, token in ipairs(conf.headers) do
      if token ~= "off" and not HEADER_KEY_TO_NAME[string.lower(token)] then
        errors[#errors + 1] = fmt("headers: invalid entry '%s'",
                                  tostring(token))
      end
    end
  end

  if conf.dns_resolver then
    for _, server in ipairs(conf.dns_resolver) do
      local dns = utils.normalize_ip(server)

      if not dns or dns.type == "name" then
        errors[#errors + 1] = "dns_resolver must be a comma separated list " ..
                              "in the form of IPv4/6 or IPv4/6:port, got '"  ..
                              server .. "'"
      end
    end
  end

  if conf.dns_hostsfile then
    if not pl_path.isfile(conf.dns_hostsfile) then
      errors[#errors + 1] = "dns_hostsfile: file does not exist"
    end
  end

  if conf.dns_order then
    local allowed = { LAST = true, A = true, CNAME = true, SRV = true }

    for _, name in ipairs(conf.dns_order) do
      if not allowed[name:upper()] then
        errors[#errors + 1] = fmt("dns_order: invalid entry '%s'",
                                  tostring(name))
      end
    end
  end

  if not conf.lua_package_cpath then
    conf.lua_package_cpath = ""
  end

  -- checking the trusted ips
  for _, address in ipairs(conf.trusted_ips) do
    if not ip.valid(address) and not address == "unix:" then
      errors[#errors + 1] = "trusted_ips must be a comma separated list in " ..
                            "the form of IPv4 or IPv6 address or CIDR "      ..
                            "block or 'unix:', got '" .. address .. "'"
    end
  end

  return #errors == 0, errors[1], errors
end

local function get_file_value(path, file_name)
  local fully_qualified_path = pl_path.join(path, file_name)

  if pl_path.exists(fully_qualified_path) then
    local f = io.open(fully_qualified_path, "r")
    if f~=nil then
      local line
      line = f:read()
      f:close(f)
      return line
    else
      return nil
    end
  else
    return nil
  end
end


local function log_print_override(override_type, key_name, override_name, override_value)
  local to_print = override_value

  if CONF_SENSITIVE[key_name] then
    to_print = CONF_SENSITIVE_PLACEHOLDER
  end

  log.debug('%s %s found with "%s"', override_name, override_type, to_print)
end


local function overrides(k, default_v, file_conf, arg_conf)
  local value -- definitive value for this property

  -- default values have lowest priority

  if file_conf and file_conf[k] == nil then
    -- PL will ignore empty strings, so we need a placeholer (NONE)
    value = default_v == "NONE" and "" or default_v
  else
    value = file_conf[k] -- given conf values have middle priority
  end

  -- environment variables have higher priority

  local env_name = "KONG_" .. string.upper(k)
  local env = os.getenv(env_name)
  if env ~= nil then
    log_print_override("ENV", k, env_name, env)
    value = env
  end

  -- secrets in file mounts have higher priority

  local file_secret = get_file_value(secret_path, k)
  if file_secret ~= nil then
     log_print_override("FILE SECRET", k, k, file_secret)
     value = file_secret
  end

  -- arg_conf have highest priority
  if arg_conf and arg_conf[k] ~= nil then
    value = arg_conf[k]
  end

  return value, k
end


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


-- Parses a listener address line.
-- Supports multiple (comma separated) addresses, with 'ssl' and 'http2' flags.
-- Pre- and postfixed whitespace as well as comma's are allowed.
-- "off" as a first entry will return empty tables.
-- @value list of entries (strings)
-- @return list of parsed entries, each entry having fields `ip` (normalized string)
-- `port` (number), `ssl` (bool), `http2` (bool), `listener` (string, full listener)
local function parse_listeners(values)
  local list = {}
  local flags = { "ssl", "http2", "proxy_protocol" }
  local usage = "must be of form: [off] | <ip>:<port> [" ..
                concat(flags, "] [") .. "], [... next entry ...]"

  if pl_stringx.strip(values[1]) == "off" then
    return list
  end

  for _, entry in ipairs(values) do
    -- parse the flags
    local remainder, listener, cleaned_flags = parse_option_flags(entry, flags)

    -- verify IP for remainder
    local ip

    if utils.hostname_type(remainder) == "name" then
      -- it's not an IP address, so a name/wildcard/regex
      ip = {}
      ip.host, ip.port = remainder:match("(.+):([%d]+)$")

    else
      -- It's an IPv4 or IPv6, normalize it
      ip = utils.normalize_ip(remainder)
      -- nginx requires brackets in IPv6 addresses, but normalize_ip does
      -- not include them (due to backwards compatibility with its other uses)
      if ip and ip.type == "ipv6" then
        ip.host = "[" .. ip.host .. "]"
      end
    end

    if not ip or not ip.port then
      return nil, usage
    end

    listener.ip = ip.host
    listener.port = ip.port
    listener.listener = ip.host .. ":" .. ip.port ..
                        (#cleaned_flags == 0 and "" or " " .. cleaned_flags)

    table.insert(list, listener)
  end

  return list
end


local function parse_nginx_directives(dyn_key_prefix, conf)
  conf = conf or {}
  local directives = {}

  for k, v in pairs(conf) do
    if type(k) == "string" then
      local directive = string.match(k, dyn_key_prefix .. "(.+)")
      if directive then
        if tonumber(v) then
          v = string.format("%q", v)
        end

        table.insert(directives, { name = directive, value = v })
      end
    end
  end

  return directives
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
  if not defaults then
    return nil, "could not load default conf: " .. err
  end

  ---------------------
  -- Configuration file
  ---------------------

  local from_file_conf = {}
  if path and not pl_path.exists(path) then
    -- file conf has been specified and must exist
    return nil, "no file at: " .. path
  end

  if not path then
    -- try to look for a conf in default locations, but no big
    -- deal if none is found: we will use our defaults.
    for _, default_path in ipairs(DEFAULT_PATHS) do
      if pl_path.exists(default_path) then
        path = default_path
        break
      end

      log.verbose("no config file found at %s", default_path)
    end
  end

  if not path then
    -- still no file in default locations
    log.verbose("no config file, skip loading")

  else
    local f, err = pl_file.read(path)
    if not f then
      return nil, err
    end

    log.verbose("reading config file at %s", path)

    local s = pl_stringio.open(f)
    from_file_conf, err = pl_config.read(s, {
      smart = false,
      list_delim = "_blank_" -- mandatory but we want to ignore it
    })
    s:close()
    if not from_file_conf then
      return nil, err
    end
  end

  -----------------------
  -- Merging & validation
  -----------------------

  do
    -- find dynamic keys that need to be loaded
    local dynamic_keys = {}

    local function find_dynamic_keys(dyn_key_prefix, t)
      t = t or {}

      for k, v in pairs(t) do
        local directive = string.match(k, "(" .. dyn_key_prefix .. ".+)")
        if directive then
          dynamic_keys[directive] = true
          t[k] = tostring(v)
        end
      end
    end

    local kong_env_vars = {}

    do
      -- get env vars prefixed with KONG_<dyn_key_prefix>
      local env_vars, err = env.read_all()
      if err then
        return nil, err
      end

      for k, v in pairs(env_vars) do
        local kong_var = string.match(string.lower(k), "^kong_(.+)")
        if kong_var then
          -- the value will be read in `overrides()`
          kong_env_vars[kong_var] = true
        end
      end
    end

    for _, dyn_key_prefix in pairs(DYNAMIC_KEY_PREFIXES) do
      find_dynamic_keys(dyn_key_prefix, custom_conf)
      find_dynamic_keys(dyn_key_prefix, kong_env_vars)
      find_dynamic_keys(dyn_key_prefix, from_file_conf)
    end

    -- union (add dynamic keys to `defaults` to prevent removal of the keys
    -- during the intersection that happens later)
    defaults = tablex.merge(defaults, dynamic_keys, true)
  end

  -- merge default conf with file conf, ENV variables and arg conf (with precedence)
  local conf = tablex.pairmap(overrides, defaults, from_file_conf, custom_conf)

  -- validation
  local ok, err, errors = check_and_infer(conf)
  if not ok then
    return nil, err, errors
  end

  conf = tablex.merge(conf, defaults) -- intersection (remove extraneous properties)

  -- nginx directives from conf
  for directives_block, dyn_key_prefix in pairs(DYNAMIC_KEY_PREFIXES) do
    local directives = parse_nginx_directives(dyn_key_prefix, conf)
    conf[directives_block] = setmetatable(directives, _nop_tostring_mt)
  end

  do
    -- print alphabetically-sorted values
    local conf_arr = {}

    for k, v in pairs(conf) do
      local to_print = v
      if CONF_SENSITIVE[k] then
        to_print = "******"
      end

      conf_arr[#conf_arr+1] = k .. " = " .. pl_pretty.write(to_print, "")
    end

    table.sort(conf_arr)

    for i = 1, #conf_arr do
      log.debug(conf_arr[i])
    end
  end

  -----------------------------
  -- Additional injected values
  -----------------------------

  do
    -- merge plugins
    local plugins = {}

    if #conf.plugins > 0 and conf.plugins[1] ~= "off" then
      for i = 1, #conf.plugins do
        local plugin_name = pl_stringx.strip(conf.plugins[i])

        if plugin_name ~= "off" then
          if plugin_name == "bundled" then
            plugins = tablex.merge(constants.BUNDLED_PLUGINS, plugins, true)

          else
            plugins[plugin_name] = true
          end
        end
      end
    end

    if conf.custom_plugins and #conf.custom_plugins > 0 then
      local warned

      for i = 1, #conf.custom_plugins do
        local plugin_name = pl_stringx.strip(conf.custom_plugins[i])

        if not plugins[plugin_name] and not warned then
          log.warn("the 'custom_plugins' configuration property is " ..
                   "deprecated, use 'plugins' instead")
          warned = true
        end

        plugins[plugin_name] = true
      end
    end

    conf.loaded_plugins = setmetatable(plugins, _nop_tostring_mt)
  end

  -- temporary workaround: inject an shm for prometheus plugin if needed
  -- TODO: allow plugins to declare shm dependencies that are automatically
  -- injected
  if conf.loaded_plugins["prometheus"] then
    local http_directives = conf["nginx_http_directives"]
    local found = false

    for _, directive in pairs(http_directives) do
      if directive.name == "lua_shared_dict"
         and string.find(directive.value, "prometheus_metrics", nil, true)
      then
         found = true
         break
      end
    end

    if not found then
      table.insert(http_directives, {
        name  = "lua_shared_dict",
        value = "prometheus_metrics 5m",
      })
    end
  end

  do
    -- nginx 'user' directive
    local user = conf.nginx_user:gsub("^%s*", "")
                                :gsub("%s$", "")
                                :gsub("%s+", " ")

    if user == "nobody" or user == "nobody nobody" then
      conf.nginx_user = nil
    end
  end

  do
    -- extract ports/listen ips
    conf.proxy_listeners, err = parse_listeners(conf.proxy_listen)
    if err then
      return nil, "proxy_listen " .. err
    end

    setmetatable(conf.proxy_listeners, _nop_tostring_mt)
    conf.proxy_ssl_enabled = false

    for _, listener in ipairs(conf.proxy_listeners) do
      if listener.ssl == true then
        conf.proxy_ssl_enabled = true
        break
      end
    end

    conf.admin_listeners, err = parse_listeners(conf.admin_listen)
    if err then
      return nil, "admin_listen " .. err
    end

    setmetatable(conf.admin_listeners, _nop_tostring_mt)
    conf.admin_ssl_enabled = false

    for _, listener in ipairs(conf.admin_listeners) do
      if listener.ssl == true then
        conf.admin_ssl_enabled = true
        break
      end
    end
  end

  do
    -- load headers configuration
    local enabled_headers = {}

    for _, v in pairs(HEADER_KEY_TO_NAME) do
      enabled_headers[v] = false
    end

    if #conf.headers > 0 and conf.headers[1] ~= "off" then
      for _, token in ipairs(conf.headers) do
        if token ~= "off" then
          enabled_headers[HEADER_KEY_TO_NAME[string.lower(token)]] = true
        end
      end
    end

    if enabled_headers.server_tokens then
      enabled_headers[HEADERS.VIA] = true
      enabled_headers[HEADERS.SERVER] = true
    end

    if enabled_headers.latency_tokens then
      enabled_headers[HEADERS.PROXY_LATENCY] = true
      enabled_headers[HEADERS.UPSTREAM_LATENCY] = true
    end

    conf.enabled_headers = setmetatable(enabled_headers, _nop_tostring_mt)
  end

  -- load absolute paths
  conf.prefix = pl_path.abspath(conf.prefix)

  if conf.ssl_cert and conf.ssl_cert_key then
    conf.ssl_cert = pl_path.abspath(conf.ssl_cert)
    conf.ssl_cert_key = pl_path.abspath(conf.ssl_cert_key)
  end

  if conf.client_ssl_cert and conf.client_ssl_cert_key then
    conf.client_ssl_cert = pl_path.abspath(conf.client_ssl_cert)
    conf.client_ssl_cert_key = pl_path.abspath(conf.client_ssl_cert_key)
  end

  if conf.admin_ssl_cert and conf.admin_ssl_cert_key then
    conf.admin_ssl_cert = pl_path.abspath(conf.admin_ssl_cert)
    conf.admin_ssl_cert_key = pl_path.abspath(conf.admin_ssl_cert_key)
  end

  -- attach prefix files paths
  for property, t_path in pairs(PREFIX_PATHS) do
    conf[property] = pl_path.join(conf.prefix, unpack(t_path))
  end

  log.verbose("prefix in use: %s", conf.prefix)

  -- initialize the dns client, so the globally patched tcp.connect method
  -- will work from here onwards.
  assert(require("kong.tools.dns")(conf))

  return setmetatable(conf, nil) -- remove Map mt
end


return setmetatable({
  load = load,

  add_default_path = function(path)
    DEFAULT_PATHS[#DEFAULT_PATHS+1] = path
  end,

  get_secrets_path = function()
    return secret_path
  end,

  set_secrets_path = function(path)
    secret_path = path
  end,

  remove_sensitive = function(conf)
    local purged_conf = tablex.deepcopy(conf)

    for k in pairs(CONF_SENSITIVE) do
      if purged_conf[k] then
        purged_conf[k] = CONF_SENSITIVE_PLACEHOLDER
      end
    end

    return purged_conf
  end,
}, {
  __call = function(_, ...)
    return load(...)
  end,
})
