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
local time = ngx.time
local exiting = ngx.worker.exiting
local get_phase = ngx.get_phase
local fmt = string.format
local sub = string.sub
local byte = string.byte
local gsub = string.gsub
local type = type
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
local parse_url = require("socket.url").parse
local parse_path = require("socket.url").parse_path
local encode_base64url = require("ngx.base64").encode_base64url
local decode_json = cjson.decode

local ROTATION_INTERVAL = tonumber(os.getenv("KONG_VAULT_ROTATION_INTERVAL") or 60)


local function new(self)
  local ROTATION_SEMAPHORE = semaphore.new(1)
  local ROTATION_WAIT = 0


  local REFERENCES = {}
  local FAILED = {}


  local LRU = lrucache.new(1000)


  local KEY_BUFFER = buffer.new(100)


  local RETRY_LRU = lrucache.new(1000)
  local RETRY_SEMAPHORE = semaphore.new(1)
  local RETRY_WAIT = 1
  local RETRY_TTL = 10


  local STRATEGIES = {}
  local SCHEMAS = {}
  local CONFIGS = {}
  local CONFIG_HASHES = {}


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


  local function build_cache_key(name, resource, version, hash)
    version = version or ""
    hash = hash or ""
    return "reference:" .. name .. ":" .. resource .. ":" .. version .. ":" .. hash
  end


  local function validate_value(value, err, ttl, vault, resource, key, reference)
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
      return value, nil, ttl
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

    return value, nil, ttl
  end


  local function adjust_ttl(ttl, config)
    if type(ttl) ~= "number" then
      return config and config.ttl or 0
    end

    if ttl <= 0 then
      return ttl
    end

    local max_ttl = config and config.max_ttl
    if max_ttl and max_ttl > 0 and ttl > max_ttl then
      return max_ttl
    end

    local min_ttl = config and config.min_ttl
    if min_ttl and ttl < min_ttl then
      return min_ttl
    end

    return ttl
  end


  local function retrieve_value(strategy, config, hash, reference, resource, name,
                                version, key, cache, rotation, cache_only)
    local cache_key
    if cache or rotation then
      cache_key = build_cache_key(name, resource, version, hash)
    end

    local value, err, ttl
    if cache_only then
      if not cache then
        return nil, fmt("unable to load value (%s) from vault cache (%s): no cache [%s]", resource, name, reference)
      end

      value, err = cache:get(cache_key, config)

    elseif rotation then
      value = rotation[cache_key]
      if not value then
        if cache then
          value, err, ttl = cache:renew(cache_key, config, function()
            value, err, ttl = strategy.get(config, resource, version)
            if value then
              ttl = adjust_ttl(ttl, config)
              rotation[cache_key] = value
            end
            return value, err, ttl
          end)

        else
          value, err, ttl = strategy.get(config, resource, version)
          if value then
            ttl = adjust_ttl(ttl, config)
            rotation[cache_key] = value
          end
        end
      end

    elseif cache then
      value, err = cache:get(cache_key, config, function()
        value, err, ttl = strategy.get(config, resource, version)
        if value then
          ttl = adjust_ttl(ttl, config)
        end
        return value, err, ttl
      end)

    else
      value, err, ttl = strategy.get(config, resource, version)
      if value then
        ttl = adjust_ttl(ttl, config)
      end
    end

    return validate_value(value, err, ttl, name, resource, key, reference)
  end


  local function calculate_config_hash(config, schema)
    local hash
    for k in schema:each_field() do
      local v = config[k]
      if v ~= nil then
        if not hash then
          hash = true
          KEY_BUFFER:reset()
        end
        KEY_BUFFER:putf("%s=%s;", k, v)
      end
    end

    if hash then
      return encode_base64url(md5_bin(KEY_BUFFER:get()))
    end

    -- nothing configured, so hash can be nil
    return nil
  end


  local function calculate_config_hash_for_prefix(config, schema, prefix)
    local hash = CONFIG_HASHES[prefix]
    if hash then
      return hash ~= true and hash or nil
    end

    local hash = calculate_config_hash(config, schema)

    -- true is used as to store `nil` hash
    CONFIG_HASHES[prefix] = hash or true

    return hash
  end


  local function get_config_with_overrides(base_config, config_overrides, schema, prefix)
    local config
    for k, f in schema:each_field() do
      local v = config_overrides[k]
      v = arguments.infer_value(v, f)
      -- TODO: should we be more visible with validation errors?
      if v ~= nil and schema:validate_field(f, v) then
        if not config then
          config = clone(base_config)
          KEY_BUFFER:reset()
          if prefix then
            local hash = calculate_config_hash_for_prefix(config, schema, prefix)
            if hash then
              KEY_BUFFER:putf("%s;", hash)
            end
          end
        end
        config[k] = v
        KEY_BUFFER:putf("%s=%s;", k, v)
      end
    end

    local hash
    if config then
      hash = encode_base64url(md5_bin(KEY_BUFFER:get()))
    end

    return config or base_config, hash
  end


  local function get_config(base_config, config_overrides, schema, prefix)
    if not config_overrides or isempty(config_overrides) then
      if not prefix then
        return base_config
      end

      local hash = calculate_config_hash_for_prefix(base_config, schema, prefix)
      return base_config, hash
    end

    return get_config_with_overrides(base_config, config_overrides, schema, prefix)
  end


  local function process_secret(reference, opts, rotation, cache_only)
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

        schema = require("kong.db.schema").new(schema.fields.config)

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

        local Schema = require("kong.db.schema")

        schema = Schema.new(require("kong.db.schema.entities.vaults"))

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

        schema = Schema.new(schema.fields.config)
      end

      STRATEGIES[name] = strategy
      SCHEMAS[name] = schema
    end

    -- base config stays the same so we can cache it
    local base_config = CONFIGS[name]
    if not base_config then
      base_config = {}
      if self and self.configuration then
        local configuration = self.configuration
        local env_name = gsub(name, "-", "_")
        for k, f in schema:each_field() do
          -- n is the entry in the kong.configuration table, for example
          -- KONG_VAULT_ENV_PREFIX will be found in kong.configuration
          -- with a key "vault_env_prefix". Environment variables are
          -- thus turned to lowercase and we just treat any "-" in them
          -- as "_". For example if your custom vault was called "my-vault"
          -- then you would configure it with KONG_VAULT_MY_VAULT_<setting>
          -- or in kong.conf, where it would be called
          -- "vault_my_vault_<setting>".
          local n = lower(fmt("vault_%s_%s", env_name, gsub(k, "-", "_")))
          local v = configuration[n]
          v = arguments.infer_value(v, f)
          -- TODO: should we be more visible with validation errors?
          -- In general it would be better to check the references
          -- and not just a format when they are stored with admin
          -- API, or in case of process secrets, when the kong is
          -- started. So this is a note to remind future us.
          -- Because current validations are less strict, it is fine
          -- to ignore it here.
          if v ~= nil and schema:validate_field(f, v) then
            base_config[k] = v
          elseif f.required and f.default ~= nil then
            base_config[k] = f.default
          end
        end
        CONFIGS[name] = base_config
      end
    end

    local config, hash = get_config(base_config, opts.config, schema)

    return retrieve_value(strategy, config, hash, reference, opts.resource, name,
                          opts.version, opts.key, self and self.vault_cache,
                          rotation, cache_only)
  end


  local function config_secret(reference, opts, rotation, cache_only)
    local prefix = opts.name
    local vaults = self.db.vaults
    local cache = self.vault_cache
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

      schema = require("kong.db.schema").new(schema.fields.config)

      STRATEGIES[name] = strategy
      SCHEMAS[name] = schema
    end

    local config, hash = get_config(vault.config, opts.config, schema, prefix)

    return retrieve_value(strategy, config, hash, reference, opts.resource, prefix,
                          opts.version, opts.key, cache, rotation, cache_only)
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


  local function get(reference, rotation, cache_only)
    local opts, err = parse_reference(reference)
    if err then
      return nil, err
    end

    local value, stale_value
    if not rotation then
      value, stale_value = LRU:get(reference)
      if value then
        return value
      end
    end

    local ttl
    if self and self.db and VAULT_NAMES[opts.name] == nil then
      value, err, ttl = config_secret(reference, opts, rotation, cache_only)
    else
      value, err, ttl = process_secret(reference, opts, rotation, cache_only)
    end

    if not value then
      if stale_value then
        if not cache_only then
          self.log.warn(err, " (returning a stale value)")
        end
        return stale_value
      end

      return nil, err
    end

    if type(ttl) == "number" and ttl > 0 then
      LRU:set(reference, value, ttl)
      REFERENCES[reference] = time() + ttl - ROTATION_INTERVAL

    elseif ttl == 0 then
      LRU:set(reference, value)
    end

    return value
  end


  local function update(options)
    if type(options) ~= "table" then
      return options
    end

    -- TODO: should we skip updating options, if it was done recently?

    -- TODO: should we have flag for disabling/enabling recursion?
    for k, v in pairs(options) do
      if k ~= "$refs" and type(v) == "table" then
        options[k] = update(v)
      end
    end

    local refs = options["$refs"]
    if type(refs) ~= "table" or isempty(refs) then
      return options
    end

    for field_name, reference in pairs(refs) do
      local value = get(reference, nil, true) -- TODO: ignoring errors?
      if value ~= nil then
        options[field_name] = value
      end
    end

    return options
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

    local key = md5_bin(KEY_BUFFER:get())
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

    local wait_ok
    local phase = get_phase()

    if phase == "init" or phase == "init_worker" then
      -- semaphore:wait can't work in init/init_worker phase
      wait_ok = false

    else
      -- grab a semaphore to limit concurrent updates to reduce calls to vaults
      local wait_err
      wait_ok, wait_err = RETRY_SEMAPHORE:wait(RETRY_WAIT)
      if not wait_ok then
        self.log.notice("waiting for semaphore failed: ", wait_err or "unknown")
      end
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


  local function rotate_secrets()
    if isempty(REFERENCES) then
      return true
    end

    local rotation = {}
    local current_time = time()

    local removals
    local removal_count = 0

    for reference, expiry in pairs(REFERENCES) do
      if exiting() then
        return true
      end

      if current_time > expiry then
        local value, err = get(reference, rotation)
        if not value then
          local fail_count = (FAILED[reference] or 0) + 1
          if fail_count < 5 then
            self.log.notice("rotating reference ", reference, " failed: ", err or "unknown")
            FAILED[reference] = fail_count

          else
            self.log.warn("rotating reference ", reference, " failed (removed from rotation): ", err or "unknown")
            if not removals then
              removals = { reference }
            else
              removals[removal_count] = reference
            end
          end
        end
      end
    end

    if removal_count > 0 then
      for i = 1, removal_count do
        local reference = removals[i]
        REFERENCES[reference] = nil
        FAILED[reference] = nil
        LRU:delete(reference)
      end
    end

    return true
  end


  local function rotate_secrets_timer(premature)
    if premature then
      return
    end

    local ok, err = ROTATION_SEMAPHORE:wait(ROTATION_WAIT)
    if ok then
      ok, err = pcall(rotate_secrets)

      ROTATION_SEMAPHORE:post()

      if not ok then
        self.log.err("rotating secrets failed (", err, ")")
      end

    elseif err ~= "timeout" then
      self.log.warn("rotating secrets failed (", err, ")")
    end
  end


  local _VAULT = {}


  local function flush_config_cache(data)
    local cache = self.vault_cache
    if cache then
      local vaults = self.db.vaults
      local old_entity = data.old_entity
      local old_prefix
      if old_entity then
        old_prefix = old_entity.prefix
        if old_prefix and old_prefix ~= ngx.null then
          CONFIG_HASHES[old_prefix] = nil
          cache:invalidate(vaults:cache_key(old_prefix))
        end
      end

      local entity = data.entity
      if entity then
        local prefix = entity.prefix
        if prefix and prefix ~= ngx.null and prefix ~= old_prefix then
          CONFIG_HASHES[prefix] = nil
          cache:invalidate(vaults:cache_key(prefix))
        end
      end
    end

    LRU:flush_all()
  end


  local initialized
  local function init_worker()
    if initialized then
      return
    end

    initialized = true

    if self.configuration.database ~= "off" then
      self.worker_events.register(flush_config_cache, "crud", "vaults")
    end

    local _, err = self.timer:named_every("secret-rotation", ROTATION_INTERVAL, rotate_secrets_timer)
    if err then
      self.log.err("could not schedule timer to rotate vault secret references: ", err)
    end
  end


  ---
  -- Flushes vault config and the references LRU cache.
  --
  -- @function kong.vault.flush
  --
  -- @usage
  -- kong.vault.flush()
  function _VAULT.flush()
    CONFIG_HASHES = {}
    LRU:flush_all()
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
  -- Helper function for secret rotation based on TTLs. Currently experimental.
  --
  -- @function kong.vault.update
  -- @tparam   table  options  options containing secrets and references (this function modifies the input options)
  -- @treturn  table           options with updated secret values
  --
  -- @usage
  -- local options = kong.vault.update({
  --   cert = "-----BEGIN CERTIFICATE-----...",
  --   key = "-----BEGIN RSA PRIVATE KEY-----...",
  --   cert_alt = "-----BEGIN CERTIFICATE-----...",
  --   key_alt = "-----BEGIN EC PRIVATE KEY-----...",
  --   ["$refs"] = {
  --     cert = "{vault://aws/cert}",
  --     key = "{vault://aws/key}",
  --     cert_alt = "{vault://aws/cert-alt}",
  --     key_alt = "{vault://aws/key-alt}",
  --   }
  -- })
  --
  -- -- or
  --
  -- local options = {
  --   cert = "-----BEGIN CERTIFICATE-----...",
  --   key = "-----BEGIN RSA PRIVATE KEY-----...",
  --   cert_alt = "-----BEGIN CERTIFICATE-----...",
  --   key_alt = "-----BEGIN EC PRIVATE KEY-----...",
  --   ["$refs"] = {
  --     cert = "{vault://aws/cert}",
  --     key = "{vault://aws/key}",
  --     cert_alt = "{vault://aws/cert-alt}",
  --     key_alt = "{vault://aws/key-alt}",
  --   }
  -- }
  -- kong.vault.update(options)
  function _VAULT.update(options)
    return update(options)
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


  function _VAULT.init_worker()
    init_worker()
  end


  return _VAULT
end


return {
  new = new,
}
