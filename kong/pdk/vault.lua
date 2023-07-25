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
local stringx = require ("pl.stringx")


local ngx = ngx
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
local split = stringx.split

local ROTATION_INTERVAL = tonumber(os.getenv("KONG_VAULT_ROTATION_INTERVAL") or 60)
local REFERENCE_IDENTIFIER = "reference"
local DAO_MAX_TTL = constants.DATABASE.DAO_MAX_TTL

local function new(self)
  -- Don't put this onto the top level of the file unless you're prepared for a surprise
  local Schema = require "kong.db.schema"

  local ROTATION_SEMAPHORE = semaphore.new(1)
  local ROTATION_WAIT = 0

  local LRU = lrucache.new(1000)
  local SHDICT = ngx.shared["kong_secrets"]

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
  do
    local vaults = self and self.configuration and self.configuration.loaded_vaults
    if vaults then
      VAULT_NAMES = {}

      for name in pairs(vaults) do
        VAULT_NAMES[name] = true
      end

    else
      VAULT_NAMES = BUNDLED_VAULTS and clone(BUNDLED_VAULTS) or {}
    end
  end


  local function build_cache_key(reference, hash)
    return REFERENCE_IDENTIFIER .. "\0" .. reference .. "\0" .. hash
  end

  ---
  -- This function extracts a subfield from a JSON object.
  -- It first decodes the JSON string into a Lua table, then checks for the presence and type of a specific key.
  --
  -- @function get_subfield
  -- @param value The JSON string to be parsed and decoded.
  -- @param key The specific subfield to be searched for within the JSON object.
  -- @return On success, returns the value associated with the specified key in the JSON object.
  -- If the key does not exist or its value is not a string, returns nil along with an error message.
  -- If the input value cannot be parsed as a JSON object, also returns nil along with an error message.
  local function get_subfield(value, key)
    -- Note that this function will only find keys in flat maps.
    -- Deeper nested structures are not supported.
    local json, err = decode_json(value)
    if type(json) ~= "table" then
      return nil, fmt("unable to json decode value (%s): %s", json, err)
    end

    value = json[key]
    if value == nil then
      return nil, fmt("subfield %s not found in JSON secret", key)
    elseif type(value) ~= "string" then
      return nil, fmt("unexpected %s value in JSON secret for subfield %s", type(value), key)
    end

    return value
  end
  ---
  -- This function adjusts the 'time-to-live' (TTL) according to the configuration provided in 'vault_config'.
  -- If the TTL is not a number or if it falls outside of the configured minimum or maximum TTL, it will be adjusted accordingly.
  --
  -- @function adjust_ttl
  -- @param ttl The initial time-to-live value.
  -- @param vault_config The configuration table for the vault, which may contain 'ttl', 'min_ttl', and 'max_ttl' fields.
  -- @return Returns the adjusted TTL. If the initial TTL is not a number, it returns the 'ttl' field from the 'vault_config' table or 0 if it doesn't exist.
  -- If the initial TTL is greater than 'max_ttl' from 'vault_config', it returns 'max_ttl'.
  -- If the initial TTL is less than 'min_ttl' from 'vault_config', it returns 'min_ttl'.
  -- Otherwise, it returns the original TTL.
  local function adjust_ttl(ttl, vault_config)
    if type(ttl) ~= "number" then
      return vault_config and vault_config.ttl or 0
    end

    local max_ttl = vault_config and vault_config.max_ttl
    if max_ttl and max_ttl > 0 and ttl > max_ttl then
      return max_ttl
    end

    local min_ttl = vault_config and vault_config.min_ttl
    if min_ttl and ttl < min_ttl then
      return min_ttl
    end

    return ttl
  end

  ---
  -- This function retrieves a vault by its prefix. It either fetches the vault from a cache or directly accesses it.
  -- The vault is expected to be found in a database (db) or cache. If not found, an error message is returned.
  --
  -- @function get_vault
  -- @param prefix The unique identifier of the vault to be retrieved.
  -- @return Returns the vault if it's found. If the vault is not found, it returns nil along with an error message.
  local function get_vault(prefix)
    -- find a vault - it can be either a named vault that needs to be loaded from the cache, or the
    -- vault type accessed by name
    local cache = self.core_cache
    local vaults = self.db.vaults
    local vault, err

    if cache then
      local vault_cache_key = vaults:cache_key(prefix)
      vault, err = cache:get(vault_cache_key, nil, vaults.select_by_prefix, vaults, prefix)
    else
      vault, err = vaults:select_by_prefix(prefix)
    end

    if vault then
      return vault
    end

    return nil, fmt("cannot find vault %s: %s", prefix, err)
  end


  local function get_vault_config_from_kong_conf(name)
    -- base config stays the same so we can cache it
    local base_config = CONFIGS[name]
    if not base_config then
      base_config = {}
      if self and self.configuration then
        local configuration = self.configuration
        local env_name = gsub(name, "-", "_")
        local schema = assert(SCHEMAS[name])
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
    return base_config
  end


  ---
  -- Fetches the strategy and schema for a given vault during initialization.
  --
  -- This function checks if the vault exists in `VAULT_NAMES`, fetches the associated strategy and schema from
  -- the `STRATEGIES` and `SCHEMAS` tables, respectively. If the strategy or schema isn't found in the tables, it
  -- attempts to fetch them from the application's database or by requiring them from a module.
  --
  -- The fetched strategy and schema are then stored back into the `STRATEGIES` and `SCHEMAS` tables for later use.
  -- If the `init` method exists in the strategy, it's also executed.
  --
  -- @function get_vault_strategy_and_schema_during_init
  -- @param name string The name of the vault to fetch the strategy and schema for.
  -- @return strategy ??? The fetched or required strategy for the given vault.
  -- @return schema ??? The fetched or required schema for the given vault.
  -- @return string|nil An error message, if an error occurred while fetching or requiring the strategy or schema.
  local function get_vault_strategy_and_schema_during_init(name)
    if not VAULT_NAMES[name] then
      return nil, nil, fmt("vault not found (%s)", name)
    end

    local strategy = STRATEGIES[name]
    local schema = SCHEMAS[name]
    if strategy and schema then
      return strategy, schema
    end

    local vaults = self and (self.db and self.db.vaults)
    if vaults and vaults.strategies then
      strategy = vaults.strategies[name]
      if not strategy then
        return nil, nil, fmt("could not find vault (%s)", name)
      end

      schema = vaults.schema.subschemas[name]
      if not schema then
        return nil, nil, fmt("could not find vault schema (%s): %s", name, strategy)
      end

      schema = Schema.new(schema.fields.config)
    else
      local ok
      ok, strategy = pcall(require, fmt("kong.vaults.%s", name))
      if not ok then
        return nil, nil, fmt("could not find vault (%s): %s", name, strategy)
      end

      local def
      ok, def = pcall(require, fmt("kong.vaults.%s.schema", name))
      if not ok then
        return nil, nil, fmt("could not find vault schema (%s): %s", name, def)
      end

      schema = Schema.new(require("kong.db.schema.entities.vaults"))

      local err
      ok, err = schema:new_subschema(name, def)
      if not ok then
        return nil, nil, fmt("could not load vault sub-schema (%s): %s", name, err)
      end

      schema = schema.subschemas[name]
      if not schema then
        return nil, nil, fmt("could not find vault sub-schema (%s)", name)
      end

      if type(strategy.init) == "function" then
        strategy.init()
      end

      schema = Schema.new(schema.fields.config)
    end

    STRATEGIES[name] = strategy
    SCHEMAS[name] = schema

    return strategy, schema
  end


  local function get_vault_strategy_and_schema(name)
    local vaults = self.db.vaults
    local strategy = STRATEGIES[name]
    local schema = SCHEMAS[name]
    if strategy then
      return strategy, schema
    end

    strategy = vaults.strategies[name]
    if not strategy then
      return nil, nil, fmt("vault not installed (%s)", name)
    end

    schema = vaults.schema.subschemas[name]
    if not schema then
      return nil, nil, fmt("could not find vault sub-schema (%s)", name)
    end

    schema = Schema.new(schema.fields.config)

    STRATEGIES[name] = strategy
    SCHEMAS[name] = schema

    return strategy, schema
  end


  local function get_config_and_hash(base_config, config_overrides, schema, prefix)
    local config = {}
    config_overrides = config_overrides or {}
    KEY_BUFFER:reset()
    if prefix then
      KEY_BUFFER:putf("%s;", prefix)
    end
    for k, f in schema:each_field() do
      local v = config_overrides[k] or base_config[k]
      v = arguments.infer_value(v, f)
      -- The schema:validate_field() can yield. This is problematic
      -- as this funciton is called in phases (like the body_filter) where
      -- we can't yield.
      -- It's questionable to validate at this point anyways.

      -- if v ~= nil and schema:validate_field(f, v) then
      config[k] = v
      KEY_BUFFER:putf("%s=%s;", k, v)
      -- end
    end
    return config, encode_base64url(md5_bin(KEY_BUFFER:get()))
  end


  local function get_process_strategy(parsed_reference)
    local strategy, schema, err = get_vault_strategy_and_schema_during_init(parsed_reference.name)
    if not (strategy and schema) then
      return nil, nil, nil, err
    end

    local base_config = get_vault_config_from_kong_conf(parsed_reference.name)

    return strategy, schema, base_config
  end


  local function get_config_strategy(parsed_reference)
    local vault, err = get_vault(parsed_reference.name)
    if not vault then
      return nil, nil, nil, err
    end

    local strategy, schema, err = get_vault_strategy_and_schema(vault.name)
    if not (strategy and schema) then
      return nil, nil, nil, err
    end

    return strategy, schema, vault.config
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


  --- Invokes a provided strategy to fetch a secret.
  -- This function invokes a strategy provided to it to retrieve a secret from a resource, with version control.
  -- The secret can have multiple values, each stored under a different key.
  -- The secret returned by the strategy must be a string containing a JSON object, which can be indexed by the key to get a specific value.
  -- If the secret can't be retrieved or doesn't have the expected format, appropriate errors are returned.
  --
  -- @function invoke_strategy
  -- @param strategy The strategy used to fetch the secret.
  -- @param config The configuration required by the strategy.
  -- @param parsed_reference A table containing the resource and version of the secret to be fetched, and optionally, a key to index a specific value.
  -- @return value The value of the secret or subfield if retrieval is successful.
  -- @return nil If retrieval is successful, the second returned value will be nil.
  -- @return err A string describing an error if there was one, or ttl (time to live) of the fetched secret.
  -- @usage local value, _, err = invoke_strategy(strategy, config, parsed_reference)
  -- @within Strategies
  local function invoke_strategy(strategy, config, parsed_reference)
    local value, err, ttl = strategy.get(config, parsed_reference.resource, parsed_reference.version)

    if value == nil then
      if err then
        return nil, nil, fmt("no value found (%s)", err)
      else
        return nil, nil, "no value found"
      end
    elseif type(value) ~= "string" then
      return nil, nil, fmt("value returned from vault has invalid type (%s), string expected", type(value))
    end

    -- in vault reference, the secret can have multiple values, each stored under a key.  The vault returns a JSON
    -- string that contains an object which can be indexed by the key.
    local key = parsed_reference.key
    if key then
      local sub_err
      value, sub_err = get_subfield(value, key)
      if not value then
        return nil, nil, fmt("could not get subfield value: %s", sub_err)
      end
    end

    return value, nil, ttl
  end

  --- Function `parse_and_resolve_reference` processes a reference to retrieve configuration settings,
  -- a strategy to be used, and the hash of the reference.
  -- The function first parses the reference. Then, it gets the strategy, the schema, and the base configuration
  -- settings for the vault based on the parsed reference. It checks the license type if required by the strategy.
  -- Finally, it gets the configuration and the hash of the reference.
  --
  -- @function parse_and_resolve_reference
  -- @param reference The reference to be parsed and resolved.
  -- @return The configuration, a nil value (as a placeholder for an error that did not occur),
  -- the parsed reference, the strategy to be used, and the hash of the reference.
  -- If an error occurs, it returns `nil` and an error message.
  -- @usage local config, _, parsed_reference, strategy, hash = parse_and_resolve_reference(reference)
  local function parse_and_resolve_reference(reference)

    local parsed_reference, err = parse_reference(reference)
    if not parsed_reference then
      return nil, err
    end

    local strategy, schema, base_config
    if self and self.db and VAULT_NAMES[parsed_reference.name] == nil then
      strategy, schema, base_config, err = get_config_strategy(parsed_reference)
    else
      strategy, schema, base_config, err = get_process_strategy(parsed_reference)
    end

    if not (schema and strategy) then
      return nil, fmt("could not find vault (%s) (%s)", parsed_reference.name, err or "")
    end

    if kong and kong.licensing and kong.licensing:license_type() == "free" and strategy.license_required then
      return nil, "vault " .. strategy.name .. " requires a license to be used"
    end

    local config, hash = get_config_and_hash(base_config, parsed_reference.config, schema, parsed_reference.name)

    return config, nil, parsed_reference, strategy, hash
  end

  --- Function `get_from_vault` retrieves a value from the vault using the provided strategy.
  -- The function first retrieves a value from the vault and its ttl (time-to-live).
  -- It then adjusts the ttl within configured bounds, stores the value in the SHDICT cache
  -- with a ttl that includes a resurrection time, and stores the value in the LRU cache with
  -- the adjusted ttl.
  --
  -- @function get_from_vault
  -- @param strategy The strategy to be used to retrieve the value from the vault.
  -- @param config The configuration settings to be used.
  -- @param parsed_reference The parsed reference key to lookup in the vault.
  -- @param cache_key The key to be used when storing the value in the cache.
  -- @param reference The original reference key.
  -- @return The retrieved value from the vault. If an error occurs, it returns `nil` and an error message.
  -- @usage local value, err = get_from_vault(strategy, config, parsed_reference, cache_key, reference)
  local function get_from_vault(strategy, config, parsed_reference, cache_key, reference)
    local value, ttl, err = invoke_strategy(strategy, config, parsed_reference)
    if not value then
      return nil, fmt("could not get value from external vault (%s)", err)
    end
    -- adjust ttl to the minimum and maximum values configured
    ttl = adjust_ttl(ttl, config)
    local shdict_ttl = ttl + (config.resurrect_ttl or DAO_MAX_TTL)

    -- Ignore "success" return value as we return the error to the caller.  The secret value is still valid and
    -- can be used, although the shdict does not have it.
    local store_ok, store_err = SHDICT:safe_set(cache_key, value, shdict_ttl)
    if not store_ok then
      return nil, store_err
    end

    LRU:set(reference, value, ttl)
    return value, store_err
  end

  --- Function `renew_from_vault` attempts to retrieve a value from the vault.
  -- It first parses and resolves the reference, then uses the resulting strategy,
  -- config, parsed_reference, and cache_key to attempt to get the value from the vault.
  --
  -- @function renew_from_vault
  -- @param reference The reference key to lookup in the vault.
  -- @return The retrieved value from the vault corresponding to the provided reference.
  -- If the value is not found or if an error occurs, it returns `nil` and an error message.
  -- @usage local value, err = renew_from_vault(reference)
  local function renew_from_vault(reference)
    local config, err, parsed_reference, strategy, hash = parse_and_resolve_reference(reference)

    if not config then
      return nil, err
    end
    local cache_key = build_cache_key(reference, hash)

    return get_from_vault(strategy, config, parsed_reference, cache_key, reference)
  end

  --- Function `get` retrieves a value from local (LRU) or shared dictionary (SHDICT) cache.
  -- If the value is not found in these caches and `cache_only` is not set, it attempts
  -- to retrieve the value from a vault.
  --
  -- @function get
  -- @param reference The reference key to lookup in the cache and potentially the vault.
  -- @param cache_only Optional boolean flag. If set to true, the function will not attempt
  -- to retrieve the value from the vault if it's not found in the caches.
  -- @return The retrieved value corresponding to the provided reference. If the value is
  -- not found, it returns `nil` and an error message.
  -- @usage local value, err = get(reference, cache_only)
  local function get(reference, cache_only)
    local value, _ = LRU:get(reference)
    -- Note: We should ignore the stale value here
    -- lua-resty-lrucache will always return the stale-value when
    -- the ttl has expired. As this is the worker-local cache
    -- we should defer the resurrect_ttl logic to the SHDICT
    -- which we do by adding the resurrect_ttl to the TTL

    -- If we have a worker-level cache hit, return it
    if value then
      return value
    end

    local config, err, parsed_reference, strategy, hash = parse_and_resolve_reference(reference)

    if not config then
      return nil, err
    end

    local cache_key = build_cache_key(reference, hash)

    value = SHDICT:get(cache_key)
    -- If we have a node-level cache hit, return it.
    -- Note: This will live for TTL + Resurrection Time
    if value then
      -- If we have something in the node-level cache, but not in the worker-level
      -- cache, we should update the worker-level cache. Use the remaining TTL from the SHDICT
      local lru_ttl = (SHDICT:ttl(cache_key) or 0) - (parsed_reference.resurrect_ttl or config.resurrect_ttl or DAO_MAX_TTL)
      -- only do that when the TTL is greater than 0. (0 is infinite)
      if lru_ttl > 0 then
        LRU:set(reference, value, lru_ttl)
      end
      return value
    end

    -- This forces the result from the caches. Stop here and return any value, even if nil
    if not cache_only then
      return get_from_vault(strategy, config, parsed_reference, cache_key, reference)
    end
    return nil, "could not find cached values"
  end

  --- Function `get_from_cache` retrieves values from a cache.
  --
  -- This function uses the provided references to fetch values from a cache.
  -- The fetching process will return cached values if they exist.
  --
  -- @function get_from_cache
  -- @param references A list or table of reference keys. Each reference key corresponds to a value in the cache.
  -- @return The retrieved values corresponding to the provided references. If a value does not exist in the cache for a particular reference, it is not clear from the given code what will be returned.
  -- @usage local values = get_from_cache(references)
  local function get_from_cache(references)
    return get(references, true)
  end


  --- Function `update` recursively updates a configuration table.
  --
  -- This function updates a configuration table by replacing reference fields
  -- with values fetched from a cache. The references are specified in a `$refs`
  -- field, which should be a table mapping from field names to reference keys.
  --
  -- If a reference cannot be fetched from the cache, the corresponding field is
  -- set to an empty string and an error is logged.
  --
  -- @function update
  -- @param config A table representing the configuration to update. If `config`
  -- is not a table, the function immediately returns it without any modifications.
  -- @return The updated configuration table. If the `$refs` field is not a table
  -- or is empty, the function returns `config` as is.
  -- @usage local updated_config = update(config)
  local function update(config)
    -- config should always be a table, eh?
    if type(config) ~= "table" then
      return config
    end

    for k, v in pairs(config) do
      if type(v) == "table" then
        config[k] = update(v)
      end
    end

    -- This can potentially grow without ever getting
    -- reset. This will only happen when a user repeatedly changes
    -- references without ever restarting kong, which sounds
    -- kinda unlikely, but should still be monitored.
    local refs = config["$refs"]
    if type(refs) ~= "table" or isempty(refs) then
      return config
    end

    local function update_references(refs, target)
      for field_name, field_value in pairs(refs) do
        if is_reference(field_value) then
          local value, err = get_from_cache(field_value)
          if not value then
            self.log.notice("error updating secret reference ", field_value, ": ", err)
          end
          target[field_name] = value or ''
        elseif type(field_value) == "table" then
          update_references(field_value, target[field_name])
        end
      end
    end

    update_references(refs, config)

    return config
  end

  --- Checks if the necessary criteria to perform automatic secret rotation are met.
  -- The function checks whether 'options' and 'refs' parameters are not nil and not empty.
  -- If these checks are not met, a relevant error message is returned.
  -- @local
  -- @function check_abort_criteria
  -- @tparam table options The options for the automatic secret rotation. If this parameter is nil,
  -- the function logs a notice and returns an error message.
  -- @tparam table refs The references for the automatic secret rotation. If this parameter is nil or
  -- an empty table, the function logs a notice and returns an error message.
  -- @treturn string|nil If all checks pass, the function returns nil. If any check fails, the function
  -- returns a string containing an error message.
  -- @usage check_abort_criteria(options, refs)
  local function check_abort_criteria(options, refs)
    -- If no options are provided, log a notice and return the error
    if not options then
      return "cannot automatically rotate secrets in absence of options"
    end

    -- If no references are provided, log a notice and return the error
    if not refs then
      return 'cannot automatically rotate secrets in absence of options["$refs"]'
    end

    -- If the references are empty, log a notice and return the error
    if isempty(refs) then
      return 'cannot automatically rotate secrets with empty options["$refs"]'
    end
    return nil
  end

  --- Generates sorted keys based on references.
  -- This function generates keys from a table of references and then sorts these keys.
  -- @local
  -- @function generate_sorted_keys
  -- @tparam table refs The references based on which keys are to be generated. It is expected
  -- to be a non-empty table, where the keys are strings and the values are the associated values.
  -- @treturn table keys The sorted keys from the references.
  -- @treturn number count The count of the keys.
  -- @usage local keys, count = generate_sorted_keys(refs)
  local function generate_sorted_keys(refs)
    -- Generate sorted keys based on references
    local count = nkeys(refs)
    local keys = self.table.new(count, 0)
    local i = 0
    for k in pairs(refs) do
      i = i + 1
      keys[i] = k
    end
    sort(keys)

    return keys, count
  end

  --- Populates the key buffer with sorted keys.
  -- This function takes a table of sorted keys and their corresponding count, and populates a
  -- predefined KEY_BUFFER with these keys.
  -- @local
  -- @function populate_buffer
  -- @tparam table keys The sorted keys that are to be put in the buffer.
  -- @tparam number count The count of the keys.
  -- @tparam table refs The references from which the values corresponding to the keys are obtained.
  -- @usage populate_buffer(keys, count, refs)
  local function populate_buffer(keys, count, refs)
    -- Populate the key buffer with sorted keys
    KEY_BUFFER:reset()
    for j = 1, count do
      local key = keys[j]
      local val = refs[key]
      KEY_BUFFER:putf("%s=%s;", key, val)
    end
  end

  --- Generates an LRU (Least Recently Used) cache key based on sorted keys of the references.
  -- This function generates a key for each reference, sorts these keys, and then populates a
  -- key buffer with these keys. It also generates an md5 hash of the key buffer.
  -- @local
  -- @function populate_key_buffer
  -- @tparam table refs The references based on which cache keys are to be generated.
  -- @treturn table keys The sorted keys from the references.
  -- @treturn number count The count of the keys.
  -- @treturn string md5Hash The md5 hash of the populated key buffer.
  -- @usage local keys, count, hash = populate_key_buffer(refs)
  local function populate_key_buffer(refs)
    -- Generate an LRU (Least Recently Used) cache key based on sorted keys of the references
    local keys, count = generate_sorted_keys(refs)
    populate_buffer(keys, count, refs)
    return keys, count, md5_bin(KEY_BUFFER:get())
  end

  --- Checks if a particular value has been updated compared to its previous state.
  -- @local
  -- @function is_value_updated
  -- @tparam table previous The previous state of the values.
  -- @tparam string name The name of the value to check.
  -- @tparam any value The current value to check.
  -- @treturn bool updated Returns true if the value has been updated, false otherwise.
  -- @usage local updated = is_value_updated(previous, name, value)
  local function is_value_updated(previous, name, value)
    return previous[name] ~= value
  end

  --- Checks if any values in the table have been updated compared to their previous state.
  -- @local
  -- @function values_are_updated
  -- @tparam table values The current state of the values.
  -- @tparam table previous The previous state of the values.
  -- @treturn bool updated Returns true if any value has been updated, false otherwise.
  -- @usage local updated = values_are_updated(values, previous)
  local function values_are_updated(values, previous)
    for name, value in pairs(values) do
      if is_value_updated(previous, name, value) then
        return true
      end
    end
    return false
  end

  --- Function `try` attempts to execute a provided callback function with the provided options.
  -- If the callback function fails, the `try` function will attempt to resolve references and update
  -- the values in the options table before re-attempting the callback function.
  -- NOTE: This function currently only detects changes by doing a shallow comparison. As a result, it might trigger more retries than necessary - when a config option has a table value and it seems "changed" even if the "new value" is a new table with the same keys and values inside.
  -- @function try
  -- @param callback The callback function to execute. This function should take an options table as its argument.
  -- @param options The options table to provide to the callback function. This table may include a "$refs" field which is a table mapping reference names to their values.
  -- @return Returns the result of the callback function if it succeeds, otherwise it returns `nil` and an error message.
  local function try(callback, options)
    -- Store the current references to avoid race conditions
    local previous
    local refs
    if options then
      refs = options["$refs"]
      if refs and not isempty(refs) then
        previous = {}
        for name in pairs(refs) do
          previous[name] = options[name]
        end
      end
    end

    -- Try to execute the callback with the current options
    local res, callback_err = callback(options)
    if res then
      return res -- If the callback succeeds, return the result
    end

    local abort_err = check_abort_criteria(options, refs)
    if abort_err then
      self.log.notice(abort_err)
      return nil, callback_err -- we are returning callback_error and not abort_err on purpose.
    end

    local keys, count, key = populate_key_buffer(refs)

    -- Check if there are already values cached with a certain time-to-live
    local updated
    -- The RETRY_LRU cache probaly isn't very helpful anymore.
    -- Consider removing it in further refactorings of this function.
    local values = RETRY_LRU:get(key)
    if values then
      -- If the cached values are different from the previous values, consider them as updated
      if not values_are_updated(values, previous) then
      -- If no updated values are found, return the error
        return nil, callback_err
      end
      -- Update the options with the new values and re-try the callback
      for name, value in pairs(values) do
        options[name] = value
      end
      return callback(options)
    end

    -- Semaphore cannot wait in "init" or "init_worker" phases
    local wait_ok
    local phase = get_phase()
    if phase == "init" or phase == "init_worker" then
      wait_ok = false
    else
      -- Limit concurrent updates by waiting for a semaphore
      local wait_err
      wait_ok, wait_err = RETRY_SEMAPHORE:wait(RETRY_WAIT)
      if not wait_ok then
        self.log.notice("waiting for semaphore failed: ", wait_err or "unknown")
      end
    end

    -- Check again if we now have values cached with a certain time-to-live
    values = RETRY_LRU:get(key)
    if values then
      -- Release the semaphore if we had waited for it
      if wait_ok then
        RETRY_SEMAPHORE:post()
      end

      if not values_are_updated(values, previous) then
      -- If no updated values are found, return the error
        return nil, callback_err
      end
      -- Update the options with the new values and re-try the callback
      for name, value in pairs(values) do
        options[name] = value
      end

      return callback(options)
    end

    -- If no values are cached, resolve the references directly
    local values = {}
    for i = 1, count do
      local name = keys[i]
      local ref = refs[name]
      local value, get_err
      if type(ref) == "string" then
        value, get_err = renew_from_vault(ref)
      end
      if not value then
        self.log.notice("resolving reference ", refs[name], " failed: ", get_err or "unknown")
      else
        values[name] = value
        if updated == nil and previous[name] ~= value then
          updated = true
        end
      end
    end

    -- Cache the newly resolved values
    RETRY_LRU:set(key, values, RETRY_TTL)

    -- Release the semaphore if we had waited for it
    if wait_ok then
      RETRY_SEMAPHORE:post()
    end

    -- If no updated values are found, return the error
    if not updated then
      return nil, callback_err
    end

    -- Update the options with the new values and re-try the callback
    for name, value in pairs(values) do
      options[name] = value
    end
    return callback(options)
  end

  --- Function `rotate_secrets` rotates the secrets in the shared dictionary cache (SHDICT).
  -- It iterates over all keys in the SHDICT and, if a key corresponds to a reference and the
  -- ttl of the key is less than or equal to the resurrection period, it refreshes the value
  -- associated with the reference.
  --
  -- @function rotate_secrets
  -- @return Returns `true` after it has finished iterating over all keys in the SHDICT.
  -- @usage local success = rotate_secrets()
  local function rotate_secrets(force_refresh)
    for _, key in pairs(SHDICT:get_keys(0)) do
      -- key looks like "reference\0$reference\0hash"
      local key_components = split(key, "\0")
      local identifier = key_components[1]
      local reference = key_components[2]

      -- Abort criteria, `identifier`` and `reference` must exist
      -- reference must be the "reference" identifier prefix
      if not (identifier and reference
         and identifier == REFERENCE_IDENTIFIER) then
        goto next_key
      end

      local config, err = parse_and_resolve_reference(reference)
      if not config then
        self.log.warn("could not parse reference %s (%s)", reference, err)
        goto next_key
      end

      local resurrect_ttl = config.resurrect_ttl or DAO_MAX_TTL

      -- The ttl for this key, is the TTL + the resurrect time
      -- If the TTL is still greater than the resurrect time
      -- we don't have to refresh
      if SHDICT:ttl(key) > resurrect_ttl and not force_refresh then
        goto next_key
      end

      -- we should refresh the secret at this point
      local _, err = renew_from_vault(reference)
      if err then
        self.log.warn("could not retrieve value for reference %s (%s)", reference, err)
      end
      ::next_key::
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


  local function flush_and_refresh(data)
    local cache = self.core_cache
    if cache then
      local vaults = self.db.vaults
      local old_entity = data.old_entity
      local old_prefix
      if old_entity then
        old_prefix = old_entity.prefix
        if old_prefix and old_prefix ~= ngx.null then
          cache:invalidate(vaults:cache_key(old_prefix))
        end
      end

      local entity = data.entity
      if entity then
        local prefix = entity.prefix
        if prefix and prefix ~= ngx.null and prefix ~= old_prefix then
          cache:invalidate(vaults:cache_key(prefix))
        end
      end
    end


    LRU:flush_all()
    RETRY_LRU:flush_all()
    -- We can't call SHDICT.flush_all() here as it would invalidate all
    -- available caches and without reloading the values from a vault implementation.
    -- For exmaple the plugins_iterator relies on the caches being populated.
    -- We rather force a secret-rotation in this scenarion, to avoid empty caches.
    rotate_secrets(true)
  end


  local initialized
  local function init_worker()
    if initialized then
      return
    end

    initialized = true

    if self.configuration.database ~= "off" then
      self.worker_events.register(flush_and_refresh, "crud", "vaults")
    end

    local _, err = self.timer:named_every("secret-rotation", ROTATION_INTERVAL, rotate_secrets_timer)
    if err then
      self.log.err("could not schedule timer to rotate vault secret references: ", err)
    end
  end


  ---
  -- Flushes vault config and the references in LRU cache.
  --
  -- @function kong.vault.flush
  --
  -- @usage
  -- kong.vault.flush()
  function _VAULT.flush()
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
