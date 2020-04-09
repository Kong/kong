local declarative_config = require "kong.db.schema.others.declarative_config"
local topological_sort = require "kong.db.schema.topological_sort"
local pl_file = require "pl.file"
local lyaml = require "lyaml"
local cjson = require "cjson.safe"
local tablex = require "pl.tablex"


local deepcopy = tablex.deepcopy
local null = ngx.null
local SHADOW = true
local md5 = ngx.md5
local REMOVE_FIRST_LINE_PATTERN = "^[^\n]+\n(.+)$"


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


function Config:parse_file(filename, accept, old_hash)
  if type(filename) ~= "string" then
    error("filename must be a string", 2)
  end

  local contents, err = pl_file.read(filename)
  if not contents then
    return nil, err
  end

  return self:parse_string(contents, filename, accept, old_hash)
end


function Config:parse_string(contents, filename, accept, old_hash)
  -- we don't care about the strength of the hash
  -- because declarative config is only loaded by Kong administrators,
  -- not outside actors that could exploit it for collisions
  local new_hash = md5(contents)

  if old_hash and old_hash == new_hash then
    return nil, "configuration is identical", nil, nil, old_hash
  end

  -- do not accept Lua by default
  accept = accept or { yaml = true, json = true }

  local dc_table, err
  if accept.yaml and ((not filename) or filename:match("ya?ml$")) then
    local pok
    pok, dc_table, err = pcall(lyaml.load, contents)
    if not pok then
      err = dc_table
      dc_table = nil
    end

  elseif accept.json and filename:match("json$") then
    dc_table, err = cjson.decode(contents)

  elseif accept.lua and filename:match("lua$") then
    local chunk, pok
    chunk, err = loadstring(contents)
    if chunk then
      setfenv(chunk, {})
      pok, dc_table = pcall(chunk)
      if not pok then
        err = dc_table
        dc_table = nil
      end
    end

  else
    local accepted = {}
    for k, _ in pairs(accept) do
      table.insert(accepted, k)
    end
    table.sort(accepted)
    local err = "unknown file extension (" ..
                table.concat(accepted, ", ") ..
                " " .. (#accepted == 1 and "is" or "are") ..
                " supported): " .. filename
    return nil, err, { error = err }
  end

  if dc_table ~= nil and type(dc_table) ~= "table" then
    dc_table = nil
    err = "expected an object"
  end

  if type(dc_table) ~= "table" then
    err = "failed parsing declarative configuration" ..
        (filename and " file " .. filename or "") ..
        (err and ": " .. err or "")
    return nil, err, { error = err }
  end

  return self:parse_table(dc_table, new_hash)
end


function Config:parse_table(dc_table, hash)
  if type(dc_table) ~= "table" then
    error("expected a table as input", 2)
  end

  local entities, err_t = self.schema:flatten(dc_table)
  if err_t then
    return nil, pretty_print_error(err_t), err_t
  end

  if not hash then
    hash = md5(cjson.encode(dc_table))
  end

  return entities, nil, nil, dc_table._format_version, hash
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


function declarative.export_from_db(fd)
  local schemas = {}
  for _, dao in pairs(kong.db.daos) do
    table.insert(schemas, dao.schema)
  end
  local sorted_schemas, err = topological_sort(schemas)
  if not sorted_schemas then
    return nil, err
  end

  fd:write(declarative.to_yaml_string({
    _format_version = "1.1",
  }))

  for _, schema in ipairs(sorted_schemas) do
    if schema.db_export == false then
      goto continue
    end

    local name = schema.name
    local fks = {}
    for name, field in schema:each_field() do
      if field.type == "foreign" then
        table.insert(fks, name)
      end
    end

    local first_row = true
    for row, err in kong.db[name]:each() do
      for _, fname in ipairs(fks) do
        if type(row[fname]) == "table" then
          local id = row[fname].id
          if id ~= nil then
            row[fname] = id
          end
        end
      end

      local yaml = declarative.to_yaml_string({ [name] = { row } })
      if not first_row then
        yaml = assert(yaml:match(REMOVE_FIRST_LINE_PATTERN))
      end
      first_row = false

      fd:write(yaml)
    end

    ::continue::
  end

  return true
end


function declarative.export_config()
  local schemas = {}
  for _, dao in pairs(kong.db.daos) do
    table.insert(schemas, dao.schema)
  end
  local sorted_schemas, err = topological_sort(schemas)
  if not sorted_schemas then
    return nil, err
  end

  local out = { _format_version = "1.1" }

  for _, schema in ipairs(sorted_schemas) do
    if schema.db_export == false then
      goto continue
    end

    local name = schema.name
    local fks = {}
    for name, field in schema:each_field() do
      if field.type == "foreign" then
        table.insert(fks, name)
      end
    end

    for row, err in kong.db[name]:each() do
      for _, fname in ipairs(fks) do
        if type(row[fname]) == "table" then
          local id = row[fname].id
          if id ~= nil then
            row[fname] = id
          end
        end
      end

      if not out[name] then
        out[name] = { row }

      else
        table.insert(out[name], row)
      end
    end

    ::continue::
  end

  return out
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


function declarative.get_current_hash()
  return ngx.shared.kong:get("declarative_config:hash")
end


function declarative.load_into_cache(entities, hash, shadow_page)
  -- Array of strings with this format:
  -- "<tag_name>|<entity_name>|<uuid>".
  -- For example, a service tagged "admin" would produce
  -- "admin|services|<the service uuid>"
  local tags = {}

  -- Keys: tag name, like "admin"
  -- Values: array of encoded tags, similar to the `tags` variable,
  -- but filtered for a given tag
  local tags_by_name = {}

  kong.core_cache:purge()
  kong.cache:purge()

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
        if fdata.type == "foreign" then
          if #kong.db[fdata.reference].schema.primary_key == 1 then
            table.insert(uniques, fname)
          end

        else
          table.insert(uniques, fname)
        end
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
      item = schema:transform(remove_nulls(item))
      local ok, err = kong.core_cache:safe_set(cache_key, item, shadow_page)
      if not ok then
        return nil, err
      end

      if schema.cache_key then
        local cache_key = dao:cache_key(item)
        ok, err = kong.core_cache:safe_set(cache_key, item, shadow_page)
        if not ok then
          return nil, err
        end
      end

      for _, unique in ipairs(uniques) do
        if item[unique] then
          local unique_key = item[unique]
          if type(unique_key) == "table" then
            local _
            -- this assumes that foreign keys are not composite
            _, unique_key = next(unique_key)
          end

          local cache_key = entity_name .. "|" .. unique .. ":" .. unique_key
          ok, err = kong.core_cache:safe_set(cache_key, item, shadow_page)
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

    local ok, err = kong.core_cache:safe_set(entity_name .. "|list", ids, shadow_page)
    if not ok then
      return nil, err
    end

    for ref, fids in pairs(page_for) do
      for fid, entries in pairs(fids) do
        local key = entity_name .. "|" .. ref .. "|" .. fid .. "|list"
        ok, err = kong.core_cache:safe_set(key, entries, shadow_page)
        if not ok then
          return nil, err
        end
      end
    end

    -- taggings:admin|services|list -> uuids of services tagged "admin"
    for tag_name, entity_ids_dict in pairs(taggings) do
      local key = "taggings:" .. tag_name .. "|" .. entity_name .. "|list"
      -- transform the dict into a sorted array
      local arr = {}
      local len = 0
      for id in pairs(entity_ids_dict) do
        len = len + 1
        arr[len] = id
      end
      -- stay consistent with pagination
      table.sort(arr)
      ok, err = kong.core_cache:safe_set(key, arr, shadow_page)
      if not ok then
        return nil, err
      end
    end
  end

  for tag_name, tags in pairs(tags_by_name) do
    -- tags:admin|list -> all tags tagged "admin", regardless of the entity type
    -- each tag is encoded as a string with the format "admin|services|uuid", where uuid is the service uuid
    local key = "tags:" .. tag_name .. "|list"
    local ok, err = kong.core_cache:safe_set(key, tags, shadow_page)
    if not ok then
      return nil, err
    end
  end

  -- tags|list -> all tags, with no distinction of tag name or entity type.
  -- each tag is encoded as a string with the format "admin|services|uuid", where uuid is the service uuid
  local ok, err = kong.core_cache:safe_set("tags|list", tags, shadow_page)
  if not ok then
    return nil, err
  end

  local ok, err = ngx.shared.kong:safe_set("declarative_config:hash", hash or true)
  if not ok then
    return nil, "failed to set declarative_config:hash in shm: " .. err
  end

  return true
end


function declarative.load_into_cache_with_events(entities, hash)

  -- ensure any previous update finished (we're flipped to the latest page)
  local ok, err = kong.worker_events.poll()
  if not ok then
    return nil, err
  end

  ok, err = kong.worker_events.post("balancer", "upstreams", {
    operation = "delete_all",
    entity = { id = "all", name = "all" }
  })
  if not ok then
    return nil, err
  end

  ok, err = declarative.load_into_cache(entities, hash, SHADOW)

  if ok then
    ok, err = kong.worker_events.post("declarative", "flip_config", true)
    if ok ~= "done" then
      return nil, "failed to flip declarative config cache pages: " .. (err or ok)
    end
  end

  kong.core_cache:purge(SHADOW)

  if not ok then
    return nil, err
  end

  kong.core_cache:invalidate("router:version")

  ok, err = kong.worker_events.post("balancer", "upstreams", {
    operation = "reset",
    entity = { id = "all", name = "all" }
  })
  if not ok then
    return nil, err
  end

  ok, err = kong.worker_events.post("balancer", "targets", {
    operation = "reset",
    entity = { id = "all", name = "all" }
  })
  if not ok then
    return nil, err
  end

  return true
end


return declarative
