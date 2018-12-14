local declarative_config = require "kong.db.schema.others.declarative_config"
local topological_sort = require "kong.db.schema.topological_sort"
local pl_file = require "pl.file"
local lyaml = require "lyaml"
local cjson = require "cjson.safe"
local tablex = require "pl.tablex"


local ngx_get_phase = ngx.get_phase
local deepcopy = tablex.deepcopy
local null = ngx.null


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

  return entities, dc_table._format_version
end


function declarative.to_yaml_string(entities)
  local pok, yaml, err = pcall(lyaml.dump, {entities})
  if not pok then
    return nil, yaml
  end
  if not yaml then
    return nil, err
  end

  -- drop the multi-document "---\n" header and "\n..." trailer
  return yaml:sub(5, -5)
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


local function post_upstream_crud_delete_events()
  local upstreams = kong.cache:get("upstreams|list", nil, function()
    return nil
  end)
  if upstreams then
    for _, id in ipairs(upstreams) do
      local _, err = kong.worker_events.post("crud", "upstreams", {
        operation = "delete",
        entity = {
          id = id,
          name = "?", -- only used for error messages
        },
      })
      if err then
        kong.log.err("failed posting invalidation event for upstream ", id)
      end
    end
  end
end


local function post_crud_create_event(entity_name, item)
  local _, err = kong.worker_events.post("crud", entity_name, {
    operation = "create",
    entity = item,
  })
  if err then
    kong.log.err("failed posting crud event for ", entity_name, " ", entity_name.id)
  end
end


function declarative.load_into_cache(entities)

  -- FIXME atomicity of cache update
  -- FIXME track evictions (and do something when they happen)

  local phase = ngx_get_phase()
  if phase ~= "init_worker" then
    post_upstream_crud_delete_events()
    kong.cache:purge()
  end

  -- Array of strings with this format:
  -- "<tag_name>|<entity_name>|<uuid>".
  -- For example, a service tagged "admin" would produce
  -- "admin|services|<the service uuid>"
  local tags = {}

  -- Keys: tag name, like "admin"
  -- Values: array of encoded tags, similar to the `tags` variable,
  -- but filtered for a given tag
  local tags_by_name = {}

  for entity_name, items in pairs(entities) do
    local dao = kong.db[entity_name]
    local schema = dao.schema

    -- Keys: tag_name, eg "admin"
    -- Values: dictionary of uuids associated to this tag,
    --         for a specific entity type
    --         i.e. "all the services associated to the 'admin' tag"
    --         The ids are keys, and the values are `true`
    local taggings = {}

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
      local ok, err = kong.cache:get(cache_key, nil, function()
        return item
      end)
      if not ok then
        return nil, err
      end

      if schema.cache_key then
        local cache_key = dao:cache_key(item)
        ok, err = kong.cache:get(cache_key, nil, function()
          return item
        end)
        if not ok then
          return nil, err
        end
      end

      for _, unique in ipairs(uniques) do
        if item[unique] then
          local cache_key = entity_name .. "|" .. unique .. ":" .. item[unique]
          ok, err = kong.cache:get(cache_key, nil, function()
            return item
          end)
          if not ok then
            return nil, err
          end
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

      if item.tags then
        for _, tag_name in ipairs(item.tags) do
          table.insert(tags, tag_name .. "|" .. entity_name .. "|" .. id)

          tags_by_name[tag_name] = tags_by_name[tag_name] or {}
          table.insert(tags_by_name[tag_name], tag_name .. "|" .. entity_name .. "|" .. id)

          taggings[tag_name] = taggings[tag_name] or {}
          taggings[tag_name][id] = true
        end
      end
    end

    local ok, err = kong.cache:get(entity_name .. "|list", nil, function()
      return ids
    end)
    if not ok then
      return nil, err
    end

    for ref, fids in pairs(page_for) do
      for fid, entries in pairs(fids) do
        local key = entity_name .. "|" .. ref .. "|" .. fid .. "|list"
        ok, err = kong.cache:get(key, nil, function()
          return entries
        end)
        if not ok then
          return nil, err
        end
      end
    end

    -- taggings:admin|services|list -> uuids of services tagged "admin"
    for tag_name, entity_ids_dict in pairs(taggings) do
      local key = "taggings:" .. tag_name .. "|" .. entity_name .. "|list"
      ok, err = kong.cache:get(key, nil, function()
        -- transform the dict into a sorted array
        local arr = {}
        local len = 0
        for id in pairs(entity_ids_dict) do
          len = len + 1
          arr[len] = id
        end
        -- stay consistent with pagination
        table.sort(arr)
        return arr
      end)
      if not ok then
        return nil, err
      end
    end
  end

  for tag_name, tags in pairs(tags_by_name) do
    -- tags:admin|list -> all tags tagged "admin", regardless of the entity type
    -- each tag is encoded as a string with the format "admin|services|uuid", where uuid is the service uuid
    local key = "tags:" .. tag_name .. "|list"
    local ok, err = kong.cache:get(key, nil, function()
      -- print(require("inspect")({ [key] = tags }))
      return tags
    end)
    if not ok then
      return nil, err
    end
  end

  -- tags|list -> all tags, with no distinction of tag name or entity type.
  -- each tag is encoded as a string with the format "admin|services|uuid", where uuid is the service uuid
  local ok, err = kong.cache:get("tags|list", nil, function()
    -- print(require("inspect")({ ["tags|list"] = tags }))
    return tags
  end)
  if not ok then
    return nil, err
  end

  local ok, err = ngx.shared.kong:safe_add("declarative_config:loaded", true)
  if not ok and err ~= "exists" then
    return nil, "failed to set declarative_config:loaded in shm: " .. err
  end

  for _, entity_name in ipairs({"upstreams", "targets"}) do
    if entities[entity_name] then
      for _, item in pairs(entities[entity_name]) do
        post_crud_create_event(entity_name, item)
      end
    end
  end

  if phase ~= "init_worker" then
    kong.cache:invalidate("router:version")
  end

  return true
end


return declarative
