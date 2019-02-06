local declarative_config = require "kong.db.schema.others.declarative_config"
local topological_sort = require "kong.db.schema.topological_sort"
local pl_file = require "pl.file"
local lyaml = require "lyaml"
local cjson = require "cjson.safe"
local tablex = require "pl.tablex"


local deepcopy = tablex.deepcopy


local declarative = {}


local Config = {}


-- Produce an instance of the declarative config schema, tailored for a
-- specific list of plugins (and their configurations and custom
-- entities) from a given Kong config.
-- @tparam table kong_config The Kong configuration table
-- @treturn table A Config schema adjusted for this configuration
function declarative.new_config(kong_config)
  local schema, err = declarative_config.load(kong_config.loaded_plugins)
  if not schema then
    return nil, err
  end

  local self = {
    schema = schema
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
        table.insert(out, indent .. prettykey .. ":")
        table.insert(out, pretty_print_error(v, k, indent .. "  "))
      else
        table.insert(out, indent .. prettykey .. ": " .. v)
      end
    end
  end
  return table.concat(out, "\n")
end


function Config:parse_file(filename, accept)
  if type(filename) ~= "string" then
    error("filename must be a string", 2)
  end

  local contents, err = pl_file.read(filename)
  if not contents then
    return nil, err
  end

  return self:parse_string(contents, filename, accept)
end


function Config:parse_string(contents, filename, accept)

  -- do not accept Lua by default
  accept = accept or { yaml = true, json = true }

  local dc_table, err
  if accept.yaml and filename:match("ya?ml$") then
    local pok
    pok, dc_table, err = pcall(lyaml.load, contents)
    if not pok then
      err = dc_table
      dc_table = nil
    end

  elseif accept.json and filename:match("json$") then
    dc_table, err = cjson.decode(contents)

  elseif accept.lua and filename:match("lua$") then
    local chunk = loadstring(contents)
    setfenv(chunk, {})
    if chunk then
      local pok, dc_table = pcall(chunk)
      if not pok then
        err = dc_table
      end
    end

  else
    local accepted = {}
    for k, _ in pairs(accept) do
      table.insert(accepted, k)
    end
    table.sort(accepted)
    return nil, "unknown file extension (" ..
                table.concat(accepted, ", ") ..
                " " .. (#accepted == 1 and "is" or "are") ..
                " supported): " .. filename
  end

  if not dc_table then
    return nil, "failed parsing declarative configuration file " ..
        filename .. (err and ": " .. err or "")
  end

  local ok, err_t = self.schema:validate(dc_table)
  if not ok then
    return nil, pretty_print_error(err_t), err_t
  end

  local entities
  entities, err_t = self.schema:flatten(dc_table)
  if err_t then
    return nil, pretty_print_error(err_t), err_t
  end

  return entities
end


function declarative.load_into_db(dc_table)
  assert(type(dc_table) == "table")

  local schemas = {}
  for entity_name, _ in pairs(dc_table) do
    table.insert(schemas, kong.db[entity_name].schema)
  end
  local sorted_schemas, err = topological_sort(schemas)
  if not sorted_schemas then
    return nil, err
  end

  local schema, primary_key, ok, err, err_t
  for i = 1, #sorted_schemas do
    schema = sorted_schemas[i]
    for _, entity in pairs(dc_table[schema.name]) do
      entity = deepcopy(entity)
      entity._tags = nil

      primary_key = schema:extract_pk_values(entity)

      ok, err, err_t = kong.db[schema.name]:upsert(primary_key, entity)
      if not ok then
        return nil, err, err_t
      end
    end
  end

  return true
end


return declarative
