local DEFAULT_PATHS = {
  "/etc/kong.conf",
  "/etc/kong/kong.conf"
}

local CONF_SCHEMA = {
  -- kong
  ssl = {typ = "boolean"},

  custom_plugins = {typ = "array"},

  database = {enum = {"postgres", "cassandra"}},
  pg_port = {typ = "number"},
  cassandra_contact_points = {typ = "array"},
  cassandra_port = {typ = "number"},
  cassandra_repl_strategy = {enum = {"SimpleStrategy", "NetworkTopologyStrategy"}},
  cassandra_repl_factor = {typ = "number"},
  cassandra_data_centers = {typ = "array"},
  cassandra_timeout = {typ = "number"},
  cassandra_consistency = {enum = {"ALL", "EACH_QUORUM", "QUORUM", "LOCAL_QUORUM", "ONE",
                                   "TWO", "THREE", "LOCAL_ONE"}}, -- no ANY: this is R/W
  cassandra_ssl = {typ = "boolean"},
  cassandra_ssl_verify = {typ = "boolean"},

  dnsmasq = {typ = "boolean"},

  anonymous_reports = {typ = "boolean"},

  -- ngx_lua
  lua_code_cache = {typ = "ngx_boolean"},

  -- nginx
  nginx_daemon = {typ = "ngx_boolean"},
  nginx_optimizations = {typ = "boolean"},
  nginx_worker_processes = {typ = "string"} -- force string inference
}

local kong_default_conf = require "kong.templates.kong_defaults"
local constants = require "kong.constants"
local pl_stringio = require "pl.stringio"
local pl_stringx = require "pl.stringx"
local pl_config = require "pl.config"
local pl_file = require "pl.file"
local pl_path = require "pl.path"
local tablex = require "pl.tablex"
local log = require "kong.cmd.utils.log"

local typ_checks = {
  array = function(v) return type(v) == "table" end,
  string = function(v) return type(v) == "string" end,
  number = function(v) return type(v) == "number" end,
  boolean = function(v) return type(v) == "boolean" end,
  ngx_boolean = function(v) return v == "on" or v == "off" end,
}

local function check_and_infer(conf)
  local errors = {}

  for k, value in pairs(conf) do
    local v_schema = CONF_SCHEMA[k] or {}
    local typ = v_schema.typ

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

    if type(value) == "string" then
      -- default type is string, and an empty if unset
      value = value ~= "" and tostring(value) or nil
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

  -- custom validation
  if conf.ssl then
    if not conf.ssl_cert then
      errors[#errors+1] = "ssl_cert required if SSL enabled"
    elseif not conf.ssl_cert_key then
      errors[#errors+1] = "ssl_cert_key required if SSL enabled"
    end
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
    log.debug("%s ENV found with %s", env_name, env)
    value = env
  end

  -- arg_conf have highest priority
  if arg_conf and arg_conf[k] ~= nil then
    value = arg_conf[k]
  end

  log.debug("%s = %s", k, value)

  return value, k
end

-- @param[type=string] path A path to a conf file
-- @param[type=table] custom_conf A table taking precedence over all other sources.
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

  if path then -- we have a file? then load it
    local f, err = pl_file.read(path)
    if not f then return nil, err end

    log.verbose("reading config file at "..path)
    local s = pl_stringio.open(f)
    from_file_conf, err = pl_config.read(s)
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

  do
    -- merge plugins
    local custom_plugins = {}
    for i = 1, #conf.custom_plugins do
      local plugin_name = conf.custom_plugins[i]
      custom_plugins[plugin_name] = true
    end
    conf.plugins = tablex.merge(constants.PLUGINS_AVAILABLE, custom_plugins, true)
    conf.custom_plugins = nil
  end

  log.verbose("prefix in use: "..conf.prefix)

  return setmetatable(conf, nil) -- remove Map mt
end

return load
