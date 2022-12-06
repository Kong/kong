local declarative_config = require "kong.db.schema.others.declarative_config"
local pl_file = require "pl.file"
local lyaml = require "lyaml"
local cjson = require "cjson.safe"
local utils = require "kong.tools.utils"
local on_the_fly_migration = require "kong.db.declarative.migrations.route_path"
local declarative_import = require "kong.db.declarative.import"
local declarative_export = require "kong.db.declarative.export"

local setmetatable = setmetatable
local tostring = tostring
local insert = table.insert
local concat = table.concat
local error = error
local pcall = pcall
local type = type
local null = ngx.null
local md5 = ngx.md5
local pairs = pairs
local yield = utils.yield
local cjson_decode = cjson.decode
local cjson_encode = cjson.encode
local convert_nulls = declarative_export.convert_nulls


local declarative = {}


local Config = {}


-- Produce an instance of the declarative config schema, tailored for a
-- specific list of plugins (and their configurations and custom
-- entities) from a given Kong config.
-- @tparam table kong_config The Kong configuration table
-- @tparam boolean partial Input is not a full representation
-- of the database (e.g. for db_import)
-- @treturn table A Config schema adjusted for this configuration
function declarative.new_config(kong_config, partial)
  local schema, err = declarative_config.load(kong_config.loaded_plugins, kong_config.loaded_vaults)
  if not schema then
    return nil, err
  end

  local self = {
    schema = schema,
    partial = partial,
  }
  setmetatable(self, { __index = Config })
  return self
end


-- This is the friendliest we can do without a YAML parser
-- that preserves line numbers
local function pretty_print_error(err_t, item, indent)
  indent = indent or ""
  local out = {}
  local done = {}
  for k, v in pairs(err_t) do
    if not done[k] then
      local prettykey = (type(k) == "number")
                        and "- in entry " .. k .. " of '" .. item .. "'"
                        or  "in '" .. k .. "'"
      if type(v) == "table" then
        insert(out, indent .. prettykey .. ":")
        insert(out, pretty_print_error(v, k, indent .. "  "))
      else
        insert(out, indent .. prettykey .. ": " .. v)
      end
    end
  end
  return concat(out, "\n")
end


-- @treturn table|nil a table with the following format:
--   {
--     services: {
--       ["<uuid>"] = { ... },
--       ...
--     },

--   }
-- @treturn nil|string error message, only if error happened
-- @treturn nil|table err_t, only if error happened
-- @treturn table|nil a table with the following format:
--   {
--     _format_version: "2.1",
--     _transform: true,
--   }
function Config:parse_file(filename, old_hash)
  if type(filename) ~= "string" then
    error("filename must be a string", 2)
  end

  local contents, err = pl_file.read(filename)
  if not contents then
    return nil, err
  end

  return self:parse_string(contents, filename, old_hash)
end


-- @treturn table|nil a table with the following format:
--   {
--     services: {
--       ["<uuid>"] = { ... },
--       ...
--     },

--   }
-- @tparam string contents the json/yml/lua being parsed
-- @tparam string|nil filename. If nil, json will be tried first, then yaml
-- @tparam string|nil old_hash used to avoid loading the same content more than once, if present
-- @treturn nil|string error message, only if error happened
-- @treturn nil|table err_t, only if error happened
-- @treturn table|nil a table with the following format:
--   {
--     _format_version: "2.1",
--     _transform: true,
--   }
function Config:parse_string(contents, filename, old_hash)
  -- we don't care about the strength of the hash
  -- because declarative config is only loaded by Kong administrators,
  -- not outside actors that could exploit it for collisions
  local new_hash = md5(contents)

  if old_hash and old_hash == new_hash then
    local err = "configuration is identical"
    return nil, err, { error = err }, nil
  end

  local tried_one = false
  local dc_table, err
  if filename == nil or filename:match("json$")
  then
    tried_one = true
    dc_table, err = cjson_decode(contents)
  end

  if type(dc_table) ~= "table"
    and (filename == nil or filename:match("ya?ml$"))
  then
    tried_one = true
    local pok
    pok, dc_table, err = pcall(lyaml.load, contents)
    if not pok then
      err = dc_table
      dc_table = nil

    elseif type(dc_table) == "table" then
      convert_nulls(dc_table, lyaml.null, null)

    else
      err = "expected an object"
      dc_table = nil
    end
  end

  if type(dc_table) ~= "table" then
    if not tried_one then
      err = "unknown file type: " ..
            tostring(filename) ..
            ". (Accepted types: json, yaml)"
    else
      err = "failed parsing declarative configuration" .. (err and (": " .. err) or "")
    end

    return nil, err, { error = err }
  end

  return self:parse_table(dc_table, new_hash)
end


-- @tparam dc_table A table with the following format:
--   {
--     _format_version: "2.1",
--     _transform: true,
--     services: {
--       ["<uuid>"] = { ... },
--       ...
--     },
--   }
--   This table is not flattened: entities can exist inside other entities
-- @treturn table|nil A table with the following format:
--   {
--     services: {
--       ["<uuid>"] = { ... },
--       ...
--     },
--   }
--   This table is flattened - there are no nested entities inside other entities
-- @treturn nil|string error message if error
-- @treturn nil|table err_t if error
-- @treturn table|nil A table with the following format:
--   {
--     _format_version: "2.1",
--     _transform: true,
--   }
-- @treturn string|nil given hash if everything went well,
--                     new hash if everything went well and no given hash,
function Config:parse_table(dc_table, hash)
  if type(dc_table) ~= "table" then
    error("expected a table as input", 2)
  end

  local entities, err_t, meta = self.schema:flatten(dc_table)
  if err_t then
    return nil, pretty_print_error(err_t), err_t
  end

  on_the_fly_migration(entities, dc_table._format_version)

  yield()

  if not self.partial then
    self.schema:insert_default_workspace_if_not_given(entities)
  end

  if not hash then
    hash = md5(cjson_encode({ entities, meta }))
  end

  return entities, nil, nil, meta, hash
end


function declarative.sanitize_output(entities)
  entities.workspaces = nil

  for _, s in pairs(entities) do -- set of entities
    for _, e in pairs(s) do -- individual entity
      e.ws_id = nil
    end
  end
end


-- export
declarative.to_yaml_string              = declarative_export.to_yaml_string
declarative.to_yaml_file                = declarative_export.to_yaml_file
declarative.export_from_db              = declarative_export.export_from_db
declarative.export_config               = declarative_export.export_config
declarative.export_config_proto         = declarative_export.export_config_proto


-- import
declarative.get_current_hash            = declarative_import.get_current_hash
declarative.unique_field_key            = declarative_import.unique_field_key
declarative.load_into_db                = declarative_import.load_into_db
declarative.load_into_cache             = declarative_import.load_into_cache
declarative.load_into_cache_with_events = declarative_import.load_into_cache_with_events


return declarative
