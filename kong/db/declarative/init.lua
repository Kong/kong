local declarative_config = require "kong.db.schema.others.declarative_config"
local topological_sort = require "kong.db.schema.topological_sort"
local lyaml = require "lyaml"
local cjson = require "cjson.safe"
local tablex = require "pl.tablex"


local deepcopy = tablex.deepcopy
local null = ngx.null


local declarative = {}


local Declarative = {}


function declarative.init(conf)
  local schema, err = declarative_config.load(conf.loaded_plugins)
  if not schema then
    return nil, err
  end

  local self = {
    schema = schema
  }
  setmetatable(self, { __index = Declarative })
  return self
end


function Declarative:parse_file(filename, accept)
  assert(type(filename) == "string")

  local fd, err = io.open(filename)
  if not fd then
    return nil, "could not open declarative configuration file: " ..
                filename .. ": " .. err
  end

  local contents, err = fd:read("*a")
  if not contents then
    return nil, "could not read declarative configuration file: " ..
                filename .. ": " .. err
  end

  assert(fd:close())

  return self:parse_string(contents, filename, accept)
end


function Declarative:parse_string(contents, filename, accept)

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

  local ok, err = self.schema:validate(dc_table)
  if not ok then
    return nil, err
  end

  local entities, err = self.schema:flatten(dc_table)
  if err then
    return nil, err
  end

  return entities
end


function declarative.to_yaml_string(entities)
  local pok, yaml, err = pcall(lyaml.dump, {entities})
  if not pok then
    return nil, yaml
  end
  if not yaml then
    return nil, err
  end

  return yaml
end


function declarative.to_yaml_file(entities, filename)
  local yaml, err = declarative.to_yaml_string(entities)
  if not yaml then
    return nil, err
  end

  local fd, err = io.open(filename, "w")
  if not fd then
    return nil, err
  end

  local ok, err = fd:write(yaml)
  if not ok then
    return nil, err
  end

  fd:close()

  return true
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


local function remove_nulls(tbl)
  for k,v in pairs(tbl) do
    if v == null then
      tbl[k] = nil
    elseif type(v) == "table" then
      tbl[k] = remove_nulls(v)
    end
  end
  return tbl
end


function declarative.load_into_cache(entities)

  -- FIXME atomicity of cache update
  kong.cache:purge()

  for entity_name, items in pairs(entities) do
    local dao = kong.db[entity_name]
    local schema = dao.schema

    local uniques = {}
    local page_for = {}
    local foreign_fields = {}
    for fname, fdata in schema:each_field() do
      if fdata.unique then
        table.insert(uniques, fname)
      end
      if fdata.type == "foreign" then
        page_for[fdata.reference] = {}
        foreign_fields[fname] = fdata.reference
      end
    end

    local ids = {}
    for id, item in pairs(items) do
      table.insert(ids, id)

      local cache_key = dao:cache_key(id)
      item = remove_nulls(item)
      kong.cache:get(cache_key, nil, function()
        return item
      end)

      if schema.cache_key then
        local cache_key = dao:cache_key(item)
        kong.cache:get(cache_key, nil, function()
          return item
        end)
      end

      for _, unique in ipairs(uniques) do
        if item[unique] then
          local cache_key = entity_name .. "|" .. unique .. ":" .. item[unique]
          kong.cache:get(cache_key, nil, function()
            return item
          end)
        end
      end

      for fname, ref in pairs(foreign_fields) do
        if item[fname] then
          local fschema = kong.db[ref].schema

          local fid = declarative_config.pk_string(fschema, item[fname])
          page_for[ref][fid] = page_for[ref][fid] or {}
          table.insert(page_for[ref][fid], id)
        end
      end
    end

    kong.cache:get(entity_name .. "|list", nil, function()
      return ids
    end)

    for ref, fids in pairs(page_for) do
      for fid, entries in pairs(fids) do
        kong.cache:get(entity_name .. "|" .. ref .. "|" .. fid .. "|list", nil, function()
          return entries
        end)
      end
    end

  end

  kong.cache:get("declarative_config:loaded", nil, function()
    return true
  end)

  kong.cache:invalidate("router:version")
end


return declarative
