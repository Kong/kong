---
-- Vault module
--
-- This module can be used to resolve, parse and verify vault references.
--
-- @module kong.vault


local require = require


local constants = require "kong.constants"
local arguments = require "kong.api.arguments"
local semaphore = require "ngx.semaphore"
local lrucache = require "resty.lrucache"
local isempty = require "table.isempty"
local buffer = require "string.buffer"
local nkeys = require "table.nkeys"
local clone = require "table.clone"
local cjson = require("cjson.safe").new()


local ngx = ngx
local fmt = string.format
local sub = string.sub
local byte = string.byte
local gsub = string.gsub
local type = type
local next = next
local sort = table.sort
local pcall = pcall
local lower = string.lower
local pairs = pairs
local concat = table.concat
local md5_bin = ngx.md5_bin
local tostring = tostring
local tonumber = tonumber
local decode_args = ngx.decode_args
local unescape_uri = ngx.unescape_uri
local parse_url = require "socket.url".parse
local parse_path = require "socket.url".parse_path
local decode_json = cjson.decode


local function new(self)
  local LRU = lrucache.new(1000)


  local KEY_BUFFER = buffer.new(100)


  local RETRY_LRU = lrucache.new(1000)
  local RETRY_SEMAPHORE = semaphore.new(1)
  local RETRY_WAIT = 1
  local RETRY_TTL = 10


  local STRATEGIES = {}
  local SCHEMAS = {}
  local CONFIGS = {}


  local BRACE_START = byte("{")
  local BRACE_END = byte("}")
  local COLON = byte(":")
  local SLASH = byte("/")


  local BUNDLED_VAULTS = constants.BUNDLED_VAULTS
  local VAULT_NAMES
  local vaults = self and self.configuration and self.configuration.loaded_vaults
  if vaults then
    VAULT_NAMES = {}

    for name in pairs(vaults) do
      VAULT_NAMES[name] = true
    end

  else
    VAULT_NAMES = BUNDLED_VAULTS and clone(BUNDLED_VAULTS) or {}
  end


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


  local function retrieve_value(strategy, config, reference, resource,
                                name, version, key, cache, rotation)
    local cache_key
    if cache or rotation then
      cache_key = build_cache_key(name, resource, version)
    end

    local value, err
    if rotation then
      value = rotation[cache_key]
      if not value then
        value, err = strategy.get(config, resource, version)
        if value then
          rotation[cache_key] = value
          if cache then
            -- Warmup cache just in case the value is needed elsewhere.
            -- TODO: do we need to clear cache first?
            cache:get(cache_key, nil, function()
              return value, err
            end)
          end
        end
      end

    elseif cache then
      value, err = cache:get(cache_key, nil, strategy.get, config, resource, version)

    else
      value, err = strategy.get(config, resource, version)
    end

    return validate_value(value, err, name, resource, key, reference)
  end


  local function process_secret(reference, opts, rotation)
    local name = opts.name
    if not VAULT_NAMES[name] then
      return nil, fmt("vault not found (%s) [%s]", name, reference)
    end
    local strategy = STRATEGIES[name]
    local schema = SCHEMAS[name]
    if not strategy then
      local vaults = self and (self.db and self.db.vaults)
      if vaults and vaults.strategies then
        strategy = vaults.strategies[name]
        if not strategy then
          return nil, fmt("could not find vault (%s) [%s]", name, reference)
        end

        schema = vaults.schema.subschemas[name]
        if not schema then
          return nil, fmt("could not find vault schema (%s): %s [%s]", name, strategy, reference)
        end

        schema = schema.fields.config

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

        schema = require("kong.db.schema").new(require("kong.db.schema.entities.vaults"))

        local err
        ok, err = schema:new_subschema(name, def)
        if not ok then
          return nil, fmt("could not load vault sub-schema (%s): %s [%s]", name, err, reference)
        end

        schema = schema.subschemas[name]
        if not schema then
          return nil, fmt("could not find vault sub-schema (%s) [%s]", name, reference)
        end

        if type(strategy.init) == "function" then
          strategy.init()
        end

        schema = schema.fields.config
      end

      STRATEGIES[name] = strategy
      SCHEMAS[name] = schema
    end

    local config = CONFIGS[name]
    if not config then
      config = opts.config or {}
      if self and self.configuration then
        local configuration = self.configuration
        local fields = schema.fields
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

      config = arguments.infer_value(config, schema)
      CONFIGS[name] = config
    end

    return retrieve_value(strategy, config, reference, opts.resource, name,
                          opts.version, opts.key, self and self.core_cache,
                          rotation)
  end


  local function config_secret(reference, opts, rotation)
    local prefix = opts.name
    local vaults = self.db.vaults
    local cache = self.core_cache
    local vault
    local err
    if cache then
      local cache_key = vaults:cache_key(prefix)
      vault, err = cache:get(cache_key, nil, vaults.select_by_prefix, vaults, prefix)

    else
      vault, err = vaults:select_by_prefix(prefix)
    end

    if not vault then
      if err then
        return nil, fmt("vault not found (%s): %s [%s]", prefix, err, reference)
      end

      return nil, fmt("vault not found (%s) [%s]", prefix, reference)
    end

    local name = vault.name
    local strategy = STRATEGIES[name]
    local schema = SCHEMAS[name]
    if not strategy then
      strategy = vaults.strategies[name]
      if not strategy then
        return nil, fmt("vault not installed (%s) [%s]", name, reference)
      end

      schema = vaults.schema.subschemas[name]
      if not schema then
        return nil, fmt("could not find vault sub-schema (%s) [%s]", name, reference)
      end

      schema = schema.fields.config

      STRATEGIES[prefix] = strategy
      SCHEMAS[prefix] = schema
    end

    local config = opts.config
    if config then
      config = arguments.infer_value(config, schema)
      for k, v in pairs(vault.config) do
        if v ~= nil and config[k] == nil then
          config[k] = v
        end
      end

    else
      config = vault.config
    end

    return retrieve_value(strategy, config, reference, opts.resource, prefix,
                          opts.version, opts.key, cache, rotation)
  end


  local function is_reference(reference)
    return type(reference)      == "string"
       and byte(reference, 1)   == BRACE_START
       and byte(reference, -1)  == BRACE_END
       and byte(reference, 7)   == COLON
       and byte(reference, 8)   == SLASH
       and byte(reference, 9)   == SLASH
       and sub(reference, 2, 6) == "vault"
  end


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


  local function get(reference, rotation)
    local opts, err = parse_reference(reference)
    if err then
      return nil, err
    end

    local value
    if not rotation then
      value = LRU:get(reference)
      if value then
        return value
      end
    end

    if self and self.db and VAULT_NAMES[opts.name] == nil then
      value, err = config_secret(reference, opts, rotation)
    else
      value, err = process_secret(reference, opts, rotation)
    end

    if not value then
      return nil, err
    end

    LRU:set(reference, value)

    return value
  end


  local function try(callback, options)
    -- store current values early on to avoid race conditions
    local previous
    local refs
    local refs_empty
    if options then
      refs = options["$refs"]
      if refs then
        refs_empty = isempty(refs)
        if not refs_empty then
          previous = {}
          for name in pairs(refs) do
            previous[name] = options[name]
          end
        end
      end
    end

    -- try with already resolved credentials
    local res, err = callback(options)
    if res then
      return res
    end

    if not options then
      self.log.notice("cannot automatically rotate secrets in absence of options")
      return nil, err
    end

    if not refs then
      self.log.notice('cannot automatically rotate secrets in absence of options["$refs"]')
      return nil, err
    end

    if refs_empty then
      self.log.notice('cannot automatically rotate secrets with empty options["$refs"]')
      return nil, err
    end

    -- generate an LRU key
    local count = nkeys(refs)
    local keys = self.table.new(count, 0)
    local i = 0
    for k in pairs(refs) do
      i = i + 1
      keys[i] = k
    end

    sort(keys)

    KEY_BUFFER:reset()

    for i = 1, count do
      local key = keys[i]
      local val = refs[key]
      KEY_BUFFER:putf("%s=%s;", key, val)
    end

    local key = md5_bin(KEY_BUFFER:tostring())
    local updated

    -- is there already values with RETRY_TTL seconds ttl?
    local values = RETRY_LRU:get(key)
    if values then
      for name, value in pairs(values) do
        updated = previous[name] ~= value
        if updated then
          break
        end
      end

      if not updated then
        return nil, err
      end

      for name, value in pairs(values) do
        options[name] = value
      end

      -- try with updated credentials
      return callback(options)
    end

    -- grab a semaphore to limit concurrent updates to reduce calls to vaults
    local wait_ok, wait_err = RETRY_SEMAPHORE:wait(RETRY_WAIT)
    if not wait_ok then
      self.log.notice("waiting for semaphore failed: ", wait_err or "unknown")
    end

    -- do we now have values with RETRY_TTL seconds ttl?
    values = RETRY_LRU:get(key)
    if values then
      if wait_ok then
        -- release a resource
        RETRY_SEMAPHORE:post()
      end

      for name, value in pairs(values) do
        updated = previous[name] ~= value
        if updated then
          break
        end
      end

      if not updated then
        return nil, err
      end

      for name, value in pairs(values) do
        options[name] = value
      end

      -- try with updated credentials
      return callback(options)
    end

    -- resolve references without read-cache
    local rotation = {}
    local values = {}
    for i = 1, count do
      local name = keys[i]
      local value, get_err = get(refs[name], rotation)
      if not value then
        self.log.notice("resolving reference ", refs[name], " failed: ", get_err or "unknown")

      else
        values[name] = value
        if updated == nil and previous[name] ~= value then
          updated = true
        end
      end
    end

    -- set the values in LRU
    RETRY_LRU:set(key, values, RETRY_TTL)

    if wait_ok then
      -- release a resource
      RETRY_SEMAPHORE:post()
    end

    if not updated then
      return nil, err
    end

    for name, value in pairs(values) do
      options[name] = value
    end

    -- try with updated credentials
    return callback(options)
  end


  local _VAULT = {}


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
  function _VAULT.is_reference(reference)
    return is_reference(reference)
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
  function _VAULT.parse_reference(reference)
    return parse_reference(reference)
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
  function _VAULT.get(reference)
    return get(reference)
  end


  ---
  -- Helper function for automatic secret rotation. Currently experimental.
  --
  -- @function kong.vault.try
  -- @tparam   function    callback  callback function
  -- @tparam   table       options   options containing credentials and references
  -- @treturn  string|nil            return value of the callback function
  -- @treturn  string|nil            error message on failure, otherwise `nil`
  --
  -- @usage
  -- local function connect(options)
  --   return database_connect(options)
  -- end
  --
  -- local connection, err = kong.vault.try(connect, {
  --   username = "john",
  --   password = "doe",
  --   ["$refs"] = {
  --     username = "{vault://aws/database-username}",
  --     password = "{vault://aws/database-password}",
  --   }
  -- })
  function _VAULT.try(callback, options)
    return try(callback, options)
  end


  return _VAULT
end


return {
  new = new,
}
