---
-- Vault module
--
-- This module can be used to resolve, parse and verify vault references.
--
-- @module kong.vault


local require = require


local constants = require "kong.constants"
local arguments = require "kong.api.arguments"
local cjson = require("cjson.safe").new()
local clone = require "table.clone"



local ngx = ngx
local fmt = string.format
local sub = string.sub
local byte = string.byte
local gsub = string.gsub
local type = type
local next = next
local pcall = pcall
local lower = string.lower
local pairs = pairs
local concat = table.concat
local tostring = tostring
local tonumber = tonumber
local decode_args = ngx.decode_args
local unescape_uri = ngx.unescape_uri
local parse_url = require "socket.url".parse
local parse_path = require "socket.url".parse_path
local decode_json = cjson.decode


local BRACE_START = byte("{")
local BRACE_END = byte("}")
local COLON = byte(":")
local SLASH = byte("/")


local BUNDLED_VAULTS = constants.BUNDLED_VAULTS
local VAULT_NAMES


local LRU = require("resty.lrucache").new(1000)


local function build_cache_key(name, resource, version)
  return version and fmt("reference:%s:%s:%s", name, resource, version)
                  or fmt("reference:%s:%s", name, resource)
end


local function validate_value(value, err, vault, resource, key, reference)
  if type(value) ~= "string" then
    if err then
      return nil, fmt("unable to load value (%s) from vault (%s): %s [%s]", resource, vault, err, reference)
    end

    if value == nil then
      return nil, fmt("unable to load value (%s) from vault (%s): not found [%s]", resource, vault, reference)
    end

    return nil, fmt("unable to load value (%s) from vault (%s): invalid type (%s), string expected [%s]",
                    resource, vault, type(value), reference)
  end

  if not key then
    return value
  end

  local json
  json, err = decode_json(value)
  if type(json) ~= "table" then
    if err then
      return nil, fmt("unable to json decode value (%s) received from vault (%s): %s [%s]",
                      resource, vault, err, reference)
    end

    return nil, fmt("unable to json decode value (%s) received from vault (%s): invalid type (%s), table expected [%s]",
                    resource, vault, type(json), reference)
  end

  value = json[key]
  if type(value) ~= "string" then
    if value == nil then
      return nil, fmt("vault (%s) did not return value for resource '%s' with a key of '%s' [%s]",
                      vault, resource, key, reference)
    end

    return nil, fmt("invalid value received from vault (%s) for resource '%s' with a key of '%s': invalid type (%s), string expected [%s]",
                    vault, resource, key, type(value), reference)
  end

  return value
end


local function process_secret(reference, opts)
  local name = opts.name
  local kong = kong
  local vaults = kong and (kong.db and kong.db.vaults_beta)
  local strategy
  local field
  if vaults and vaults.strategies then
    strategy = vaults.strategies[name]
    if not strategy then
      return nil, fmt("could not find vault (%s) [%s]", name, reference)
    end

    local schema = vaults.schema.subschemas[name]
    if not schema then
      return nil, fmt("could not find vault schema (%s): %s [%s]", name, strategy, reference)
    end

    field = schema.fields.config

  else
    local ok
    ok, strategy = pcall(require, fmt("kong.vaults.%s", name))
    if not ok then
      return nil, fmt("could not find vault (%s): %s [%s]", name, strategy, reference)
    end

    local def
    ok, def = pcall(require, fmt("kong.vaults.%s.schema", name))
    if not ok then
      return nil, fmt("could not find vault schema (%s): %s [%s]", name, def, reference)
    end

    local schema = require("kong.db.schema").new(require("kong.db.schema.entities.vaults_beta"))

    local err
    ok, err = schema:new_subschema(name, def)
    if not ok then
      return nil, fmt("could not load vault sub-schema (%s): %s [%s]", name, err, reference)
    end

    schema = schema.subschemas[name]
    if not schema then
      return nil, fmt("could not find vault sub-schema (%s) [%s]", name, reference)
    end

    field = schema.fields.config
  end

  if strategy.init then
    strategy.init()
  end

  local resource = opts.resource
  local key = opts.key
  local config = opts.config or {}
  if kong and kong.configuration then
    local configuration = kong.configuration
    local fields = field.fields
    local env_name = gsub(name, "-", "_")
    for i = 1, #fields do
      local k, f = next(fields[i])
      if config[k] == nil then
        local n = lower(fmt("vault_%s_%s", env_name, k))
        local v = configuration[n]
        if v ~= nil then
          config[k] = v
        elseif f.required and f.default ~= nil then
          config[k] = f.default
        end
      end
    end
  end

  config = arguments.infer_value(config, field)

  local value, err = strategy.get(config, resource, opts.version)
  return validate_value(value, err, name, resource, key, reference)
end


local function config_secret(reference, opts)
  local name = opts.name
  local kong = kong
  local vaults = kong.db.vaults_beta
  local cache = kong.core_cache
  local vault
  local err
  if cache then
    local cache_key = vaults:cache_key(name)
    vault, err = cache:get(cache_key, nil, vaults.select_by_prefix, vaults, name)

  else
    vault, err = vaults:select_by_prefix(name)
  end

  if not vault then
    if err then
      return nil, fmt("vault not found (%s): %s [%s]", name, err, reference)
    end

    return nil, fmt("vault not found (%s) [%s]", name, reference)
  end

  local vname = vault.name

  local strategy = vaults.strategies[vname]
  if not strategy then
    return nil, fmt("vault not installed (%s) [%s]", vname, reference)
  end

  local schema = vaults.schema.subschemas[vname]
  if not schema then
    return nil, fmt("could not find vault sub-schema (%s) [%s]", vname, reference)
  end

  local config = opts.config
  if config then
    config = arguments.infer_value(config, schema.fields.config)
    for k, v in pairs(vault.config) do
      if v ~= nil and config[k] == nil then
        config[k] = v
      end
    end

  else
    config = vault.config
  end

  local resource = opts.resource
  local key = opts.key
  local version = opts.version

  local cache_key = build_cache_key(name, resource, version)
  local value
  if cache then
    value, err = cache:get(cache_key, nil, strategy.get, config, resource, version)
  else
    value, err = strategy.get(config, resource, version)
  end

  return validate_value(value, err, name, resource, key, reference)
end


---
-- Checks if the passed in reference looks like a reference.
-- Valid references start with '{vault://' and end with '}'.
--
-- If you need more thorough validation,
-- use `kong.vault.parse_reference`.
--
-- @function kong.vault.is_reference
-- @tparam   string   reference  reference to check
-- @treturn  boolean             `true` is the passed in reference looks like a reference, otherwise `false`
--
-- @usage
-- kong.vault.is_reference("{vault://env/key}") -- true
-- kong.vault.is_reference("not a reference")   -- false
local function is_reference(reference)
  return type(reference)      == "string"
     and byte(reference, 1)   == BRACE_START
     and byte(reference, -1)  == BRACE_END
     and byte(reference, 7)   == COLON
     and byte(reference, 8)   == SLASH
     and byte(reference, 9)   == SLASH
     and sub(reference, 2, 6) == "vault"
end


---
-- Parses and decodes the passed in reference and returns a table
-- containing its components.
--
-- Given a following resource:
-- ```lua
-- "{vault://env/cert/key?prefix=SSL_#1}"
-- ```
--
-- This function will return following table:
--
-- ```lua
-- {
--   name     = "env",  -- name of the Vault entity or Vault strategy
--   resource = "cert", -- resource where secret is stored
--   key      = "key",  -- key to lookup if the resource is secret object
--   config   = {       -- if there are any config options specified
--     prefix = "SSL_"
--   },
--   version  = 1       -- if the version is specified
-- }
-- ```
--
-- @function kong.vault.parse_reference
-- @tparam   string      reference  reference to parse
-- @treturn  table|nil              a table containing each component of the reference, or `nil` on error
-- @treturn  string|nil             error message on failure, otherwise `nil`
--
-- @usage
-- local ref, err = kong.vault.parse_reference("{vault://env/cert/key?prefix=SSL_#1}") -- table
local function parse_reference(reference)
  if not is_reference(reference) then
    return nil, fmt("not a reference [%s]", tostring(reference))
  end

  local url, err = parse_url(sub(reference, 2, -2))
  if not url then
    return nil, fmt("reference is not url (%s) [%s]", err, reference)
  end

  local name = url.host
  if not name then
    return nil, fmt("reference url is missing host [%s]", reference)
  end

  local path = url.path
  if not path then
    return nil, fmt("reference url is missing path [%s]", reference)
  end

  local resource = sub(path, 2)
  if resource == "" then
    return nil, fmt("reference url has empty path [%s]", reference)
  end

  local version = url.fragment
  if version then
    version = tonumber(version, 10)
    if not version then
      return nil, fmt("reference url has invalid version [%s]", reference)
    end
  end

  local key
  local parts = parse_path(resource)
  local count = #parts
  if count == 1 then
    resource = unescape_uri(parts[1])

  else
    resource = unescape_uri(concat(parts, "/", 1, count - 1))
    if parts[count] ~= "" then
      key = unescape_uri(parts[count])
    end
  end

  if resource == "" then
    return nil, fmt("reference url has invalid path [%s]", reference)
  end

  local config
  local query = url.query
  if query and query ~= "" then
    config = decode_args(query)
  end

  return {
    name = url.host,
    resource = resource,
    key = key,
    config = config,
    version = version,
  }
end


---
-- Resolves the passed in reference and returns the value of it.
--
-- @function kong.vault.get
-- @tparam   string      reference  reference to resolve
-- @treturn  string|nil             resolved value of the reference
-- @treturn  string|nil             error message on failure, otherwise `nil`
--
-- @usage
-- local value, err = kong.vault.get("{vault://env/cert/key}")
local function get(reference)
  local opts, err = parse_reference(reference)
  if err then
    return nil, err
  end

  local value = LRU:get(reference)
  if value then
    return value
  end

  if kong and kong.db and VAULT_NAMES[opts.name] == nil then
    value, err = config_secret(reference, opts)
  else
    value, err = process_secret(reference, opts)
  end

  if not value then
    return nil, err
  end

  LRU:set(reference, value)

  return value
end


local function new(self)
  VAULT_NAMES = BUNDLED_VAULTS and clone(BUNDLED_VAULTS) or {}

  local vaults = self and self.configuration and self.configuration.loaded_vaults
  if vaults then
    for name in pairs(vaults) do
      VAULT_NAMES[name] = true
    end
  end

  return {
    is_reference = is_reference,
    parse_reference = parse_reference,
    get = get,
  }
end


return {
  new = new,
}
