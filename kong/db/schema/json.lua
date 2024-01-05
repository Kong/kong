---
-- JSON schema validation.
--
--
local _M = {}

local lrucache = require "resty.lrucache"
local jsonschema = require "resty.ljsonschema"
local metaschema = require "resty.ljsonschema.metaschema"
local cjson = require "cjson"

local sha256_hex = require("kong.tools.sha256").sha256_hex
local cycle_aware_deep_copy = require("kong.tools.table").cycle_aware_deep_copy

local type = type
local cjson_encode = cjson.encode


---@class kong.db.schema.json.schema_doc : table
---
---@field id          string|nil
---@field ["$id"]     string|nil
---@field ["$schema"] string|nil
---@field type        string


-- The correct identifier for draft-4 is 'http://json-schema.org/draft-04/schema#'
-- with the the fragment (#) intact. Newer editions use an identifier _without_
-- the fragment (e.g. 'https://json-schema.org/draft/2020-12/schema'), so we
-- will be lenient when comparing these strings.
assert(type(metaschema.id) == "string",
       "JSON metaschema .id not defined or not a string")
local DRAFT_4_NO_FRAGMENT = metaschema.id:gsub("#$", "")
local DRAFT_4 = DRAFT_4_NO_FRAGMENT .. "#"

_M.DRAFT_4 = DRAFT_4


---@type table<string, table>
local schemas = {}


-- Creating a json schema validator is somewhat expensive as it requires
-- generating and evaluating some Lua code, so we memoize this step with
-- a local LRU cache.
local cache = lrucache.new(1000)

local schema_cache_key
do
  local cache_keys = setmetatable({}, { __mode = "k" })

  ---
  -- Generate a unique cache key for a schema document.
  --
  ---@param schema kong.db.schema.json.schema_doc
  ---@return string
  function schema_cache_key(schema)
    local cache_key = cache_keys[schema]

    if not cache_key then
      cache_key = "hash://" .. sha256_hex(cjson_encode(schema))
      cache_keys[schema] = cache_key
    end

    return cache_key
  end
end


---@param id any
---@return boolean
local function is_draft_4(id)
  return id
     and type(id) == "string"
     and (id == DRAFT_4 or id == DRAFT_4_NO_FRAGMENT)
end


---@param id any
---@return boolean
local function is_non_draft_4(id)
  return id
     and type(id) == "string"
     and (id ~= DRAFT_4 and id ~= DRAFT_4_NO_FRAGMENT)
end


---
-- Validate input according to a JSON schema document.
--
---@param  input    any
---@param  schema   kong.db.schema.json.schema_doc
---@return boolean? ok
---@return string?  error
local function validate(input, schema)
  assert(type(schema) == "table")

  -- we are validating a JSON schema document and need to ensure that it is
  -- not using supported JSON schema draft/version
  if is_draft_4(schema.id or schema["$id"])
     and is_non_draft_4(input["$schema"])
  then
    return nil, "unsupported document $schema: '" .. input["$schema"] ..
                "', expected: " .. DRAFT_4
  end

  local cache_key = schema_cache_key(schema)

  local validator = cache:get(cache_key)

  if not validator then
    validator = assert(jsonschema.generate_validator(schema, {
      name = cache_key,
      -- lua-resty-ljsonschema's default behavior for detecting an array type
      -- is to compare its metatable against `cjson.array_mt`. This is
      -- efficient, but we can't assume that all inputs will necessarily
      -- conform to this, so we opt to use the heuristic approach instead
      -- (determining object/array type based on the table contents).
      array_mt = false,
    }))
    cache:set(cache_key, validator)
  end

  return validator(input)
end


---@type table
_M.metaschema = metaschema


_M.validate = validate


---
-- Validate a JSON schema document.
--
-- This is primarily for use in `kong.db.schema.metaschema`
--
---@param  input    kong.db.schema.json.schema_doc
---@return boolean? ok
---@return string?  error
function _M.validate_schema(input)
  local typ = type(input)

  if typ ~= "table" then
    return nil, "schema must be a table"
  end

  return validate(input, _M.metaschema)
end


---
-- Add a JSON schema document to the local registry.
--
---@param name   string
---@param schema kong.db.schema.json.schema_doc
function _M.add_schema(name, schema)
  schemas[name] = cycle_aware_deep_copy(schema, true)
end


---
-- Retrieve a schema from local storage by name.
--
---@param name string
---@return table|nil schema
function _M.get_schema(name)
  return schemas[name]
end


---
-- Remove a schema from local storage by name (if it exists).
--
---@param name string
---@return table|nil schema
function _M.remove_schema(name)
  schemas[name] = nil
end


return _M
