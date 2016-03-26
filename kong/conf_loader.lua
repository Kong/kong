local DEFAULT_PATHS = {
  "/etc/kong.conf",
  "/etc/kong/kong.conf"
}

local CONF_SCHEMA = {
  -- kong
  database = {enum = {"postgres", "cassandra"}},
  dnsmasq = {typ = "boolean"},

  pg_port = {typ = "number"},

  cassandra_contact_points = {typ = "array"},
  cassandra_repl_strategy = {enum = {"SimpleStrategy", "NetworkTopologyStrategy"}},
  cassandra_repl_factor = {typ = "number"},
  cassandra_data_centers = {typ = "array"},
  cassandra_timeout = {typ = "number"},
  cassandra_consistency = {enum = {"ALL", "EACH_QUORUM", "QUORUM", "LOCAL_QUORUM", "ONE",
                                   "TWO", "THREE", "LOCAL_ONE"}}, -- no ANY: this is R/W
  cassandra_ssl = {typ = "boolean"},
  cassandra_ssl_verify = {typ = "boolean"},

  anonymous_reports = {typ = "boolean"},

  -- ngx_lua
  lua_code_cache = {typ = "boolean"},

  -- nginx
  nginx_daemon = {typ = "boolean"},
  nginx_worker_processes = {typ = "string"}
}

local kong_default_conf = require "kong.templates.kong_defaults"
local pl_stringio = require "pl.stringio"
local pl_stringx = require "pl.stringx"
local pl_config = require "pl.config"
local pl_file = require "pl.file"
local pl_path = require "pl.path"
local tablex = require "pl.tablex"

local function overrides(k, default_v, given_conf, conf_schema)
  local value -- definitive value for this property

  -- default values have lowest priority
  if given_conf[k] == nil then
    -- PL will ignore empty strings, so we need a placeholer (NONE)
    value = default_v == "NONE" and "" or default_v
  else
    -- given conf values have middle priority
    value = given_conf[k]
  end

  -- environment variables have higher priority
  local env = os.getenv("KONG_"..string.upper(k))
  if env ~= nil then
    value = env
  end

  -- transform {boolean} values ("on"/"off" aliasing to true/false)
  -- transform {explicit string} values (number values converted to strings)
  -- transform {array} values (comma-separated strings)
  if conf_schema[k] ~= nil then
    local typ = conf_schema[k].typ
    if typ == "boolean" then
      value = value == "on" or value == "true"
    elseif typ == "string" then
      value = tostring(value)
    elseif typ == "array" and type(value) == "string" then
      -- must check type because pl will already convert comma
      -- separated strings to tables (but not when the arr has
      -- only one element)
      value = setmetatable(pl_stringx.split(value, ","), nil) -- remove List mt
    end
  end

  return value, k
end

local typ_checks = {
  array = function(v) return type(v) == "table" end,
  string = function(v) return type(v) == "string" end,
  number = function(v) return type(v) == "number" end,
  boolean = function(v) return type(v) == "boolean" end
}

local function validate(conf, conf_schema)
  for k, v in pairs(conf) do
    -- type check
    local v_schema = conf_schema[k] or {}
    local typ = v_schema.typ or "string"
    if not typ_checks[typ](v) then
      return nil, k.." is not a "..typ..": '"..tostring(v).."'"
    end

    -- enum check
    if v_schema.enum and not tablex.find(v_schema.enum, v) then
      return nil, k.." has an invalid value: '"..tostring(v)
                  .."' ("..table.concat(v_schema.enum, ", ")..")"
    end
  end

  return true
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
    end
  end

  if path then -- we have a file? then load it
    local f, err = pl_file.read(path)
    if not f then return nil, err end

    local s = pl_stringio.open(f)
    from_file_conf, err = pl_config.read(s)
    s:close()
    if not from_file_conf then return nil, err end
  end

  ----------------
  -- Merging logic
  ----------------

  -- merge default conf with file conf and ENV variables (with precedence)
  local conf = tablex.pairmap(overrides, defaults, from_file_conf, CONF_SCHEMA)

  -- now, our custom_conf has the highest priority
  if type(custom_conf) == "table" then
    conf = tablex.merge(conf, custom_conf, true) -- union
  end

  local ok, err = validate(conf, CONF_SCHEMA)
  if not ok then return nil, err end

  conf = tablex.merge(conf, defaults) -- intersection (remove extraneous properties)
  return setmetatable(conf, nil) -- remove Map mt
end

return load
