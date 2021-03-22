local declarative_config = require "kong.db.schema.others.declarative_config"
local schema_topological_sort = require "kong.db.schema.topological_sort"
local workspaces = require "kong.workspaces"
local pl_file = require "pl.file"
local lyaml = require "lyaml"
local cjson = require "cjson.safe"
local tablex = require "pl.tablex"
local constants = require "kong.constants"


local deepcopy = tablex.deepcopy
local null = ngx.null
local SHADOW = true
local md5 = ngx.md5
local pairs = pairs
local ngx_socket_tcp = ngx.socket.tcp
local REMOVE_FIRST_LINE_PATTERN = "^[^\n]+\n(.+)$"
local PREFIX = ngx.config.prefix()
local SUBSYS = ngx.config.subsystem
local WORKER_COUNT = ngx.worker.count()
local DECLARATIVE_HASH_KEY = constants.DECLARATIVE_HASH_KEY


local DECLARATIVE_LOCK_KEY = "declarative:lock"
local DECLARATIVE_LOCK_TTL = 60


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
  local schema, err = declarative_config.load(kong_config.loaded_plugins)
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
        table.insert(out, indent .. prettykey .. ":")
        table.insert(out, pretty_print_error(v, k, indent .. "  "))
      else
        table.insert(out, indent .. prettykey .. ": " .. v)
      end
    end
  end
  return table.concat(out, "\n")
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


local function convert_nulls(tbl, from, to)
  for k,v in pairs(tbl) do
    if v == from then
      tbl[k] = to

    elseif type(v) == "table" then
      tbl[k] = convert_nulls(v, from, to)
    end
  end

  return tbl
end


-- @treturn table|nil a table with the following format:
--   {
--     services: {
--       ["<uuid>"] = { ... },
--       ...
--     },

--   }
-- @tparam string contents the json/yml/lua being parsed
-- @tparam string|nil filename. If nil, json will be tried first, then yaml, then lua (unless deactivated by accept)
-- @tparam table|nil table which specifies which content types are active. By default it is yaml and json only.
-- @tparam string|nil old_hash used to avoid loading the same content more than once, if present
-- @treturn nil|string error message, only if error happened
-- @treturn nil|table err_t, only if error happened
-- @treturn table|nil a table with the following format:
--   {
--     _format_version: "2.1",
--     _transform: true,
--   }
function Config:parse_string(contents, filename, accept, old_hash)
  -- we don't care about the strength of the hash
  -- because declarative config is only loaded by Kong administrators,
  -- not outside actors that could exploit it for collisions
  local new_hash = md5(contents)

  if old_hash and old_hash == new_hash then
    local err = "configuration is identical"
    return nil, err, { error = err }, nil
  end

  -- do not accept Lua by default
  accept = accept or { yaml = true, json = true }

  local tried_one = false
  local dc_table, err
  if accept.json
    and (filename == nil or filename:match("json$"))
  then
    tried_one = true
    dc_table, err = cjson.decode(contents)
  end

  if type(dc_table) ~= "table"
    and accept.yaml
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

  if type(dc_table) ~= "table"
    and accept.lua
    and (filename == nil or filename:match("lua$"))
  then
    tried_one = true
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
  end

  if type(dc_table) ~= "table" then
    if not tried_one then
      local accepted = {}
      for k, _ in pairs(accept) do
        accepted[#accepted + 1] = k
      end
      table.sort(accepted)

      err = "unknown file type: " ..
            tostring(filename) ..
            ". (Accepted types: " ..
            table.concat(accepted, ", ") .. ")"
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

  if not self.partial then
    self.schema:insert_default_workspace_if_not_given(entities)
  end

  if not hash then
    hash = md5(cjson.encode({ entities, meta }))
  end

  return entities, nil, nil, meta, hash
end


function declarative.to_yaml_string(tbl)
  convert_nulls(tbl, null, lyaml.null)
  local pok, yaml, err = pcall(lyaml.dump, { tbl })
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


local function find_or_create_current_workspace(name)
  name = name or "default"

  local workspace, err, err_t = kong.db.workspaces:select_by_name(name)
  if err then
    return nil, err, err_t
  end

  if not workspace then
    workspace, err, err_t = kong.db.workspaces:upsert_by_name(name, {
      name = name,
      no_broadcast_crud_event = true,
    })
    if err then
      return nil, err, err_t
    end
  end

  workspaces.set_workspace(assert(workspace))
  return true
end


function declarative.load_into_db(entities, meta)
  assert(type(entities) == "table")

  local schemas = {}
  for entity_name, _ in pairs(entities) do
    if kong.db[entity_name] then
      table.insert(schemas, kong.db[entity_name].schema)
    else
      return nil, "unknown entity: " .. entity_name
    end
  end
  local sorted_schemas, err = schema_topological_sort(schemas)
  if not sorted_schemas then
    return nil, err
  end

  local _, err, err_t = find_or_create_current_workspace("default")
  if err then
    return nil, err, err_t
  end

  local options = {
    transform = meta._transform,
  }
  local schema, primary_key, ok, err, err_t
  for i = 1, #sorted_schemas do
    schema = sorted_schemas[i]
    for _, entity in pairs(entities[schema.name]) do
      entity = deepcopy(entity)
      entity._tags = nil
      entity.ws_id = nil

      primary_key = schema:extract_pk_values(entity)

      ok, err, err_t = kong.db[schema.name]:upsert(primary_key, entity, options)
      if not ok then
        return nil, err, err_t
      end
    end
  end

  return true
end


local function export_from_db(emitter, skip_ws)
  local schemas = {}
  for _, dao in pairs(kong.db.daos) do
    if not (skip_ws and dao.schema.name == "workspaces") then
      table.insert(schemas, dao.schema)
    end
  end
  local sorted_schemas, err = schema_topological_sort(schemas)
  if not sorted_schemas then
    return nil, err
  end

  emitter:emit_toplevel({
    _format_version = "2.1",
    _transform = false,
  })

  for _, schema in ipairs(sorted_schemas) do
    if schema.db_export == false then
      goto continue
    end

    local name = schema.name
    local fks = {}
    for field_name, field in schema:each_field() do
      if field.type == "foreign" then
        table.insert(fks, field_name)
      end
    end

    for row, err in kong.db[name]:each(nil, { nulls = true, workspace = null }) do
      if not row then
        kong.log.err(err)
        return nil, err
      end

      for _, foreign_name in ipairs(fks) do
        if type(row[foreign_name]) == "table" then
          local id = row[foreign_name].id
          if id ~= nil then
            row[foreign_name] = id
          end
        end
      end

      emitter:emit_entity(name, row)
    end

    ::continue::
  end

  return emitter:done()
end


local fd_emitter = {
  emit_toplevel = function(self, tbl)
    self.fd:write(declarative.to_yaml_string(tbl))
  end,

  emit_entity = function(self, entity_name, entity_data)
    local yaml = declarative.to_yaml_string({ [entity_name] = { entity_data } })
    if entity_name == self.current_entity then
      yaml = assert(yaml:match(REMOVE_FIRST_LINE_PATTERN))
    end
    self.fd:write(yaml)
    self.current_entity = entity_name
  end,

  done = function()
    return true
  end,
}


function fd_emitter.new(fd)
  return setmetatable({ fd = fd }, { __index = fd_emitter })
end


function declarative.export_from_db(fd)
  return export_from_db(fd_emitter.new(fd), true)
end


local table_emitter = {
  emit_toplevel = function(self, tbl)
    self.out = tbl
  end,

  emit_entity = function(self, entity_name, entity_data)
    if not self.out[entity_name] then
      self.out[entity_name] = { entity_data }
    else
      table.insert(self.out[entity_name], entity_data)
    end
  end,

  done = function(self)
    return self.out
  end,
}


function table_emitter.new()
  return setmetatable({}, { __index = table_emitter })
end


function declarative.export_config()
  return export_from_db(table_emitter.new(), false)
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
  return ngx.shared.kong:get(DECLARATIVE_HASH_KEY)
end


local function find_default_ws(entities)
  for _, v in pairs(entities.workspaces or {}) do
    if v.name == "default" then
      return v.id
    end
  end
end


-- entities format:
--   {
--     services: {
--       ["<uuid>"] = { ... },
--       ...
--     },
--     ...
--   }
-- meta format:
--   {
--     _format_version: "2.1",
--     _transform: true,
--   }
function declarative.load_into_cache(entities, meta, hash, shadow)
  -- Array of strings with this format:
  -- "<tag_name>|<entity_name>|<uuid>".
  -- For example, a service tagged "admin" would produce
  -- "admin|services|<the service uuid>"
  local tags = {}
  meta = meta or {}

  local default_workspace = assert(find_default_ws(entities))
  local fallback_workspace = default_workspace

  assert(type(fallback_workspace) == "string")

  -- Keys: tag name, like "admin"
  -- Values: array of encoded tags, similar to the `tags` variable,
  -- but filtered for a given tag
  local tags_by_name = {}

  kong.core_cache:purge(shadow)
  kong.cache:purge(shadow)

  local transform = meta._transform == nil and true or meta._transform

  for entity_name, items in pairs(entities) do
    local dao = kong.db[entity_name]
    if not dao then
      return nil, "unknown entity: " .. entity_name
    end
    local schema = dao.schema

    -- Keys: tag_name, eg "admin"
    -- Values: dictionary of keys associated to this tag,
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

    local keys_by_ws = {
      -- map of keys for global queries
      ["*"] = {}
    }
    for id, item in pairs(items) do
      -- When loading the entities, when we load the default_ws, we
      -- set it to the current. But this only works in the worker that
      -- is doing the loading (0), other ones still won't have it

      assert(type(fallback_workspace) == "string")

      local ws_id
      if schema.workspaceable then
        if item.ws_id == null or item.ws_id == nil then
          item.ws_id = fallback_workspace
        end
        assert(type(item.ws_id) == "string")
        ws_id = item.ws_id

      else
        ws_id = ""
      end

      assert(type(ws_id) == "string")

      local cache_key = dao:cache_key(id, nil, nil, nil, nil, item.ws_id)

      item = remove_nulls(item)
      if transform then
        local err
        item, err = schema:transform(item)
        if not item then
          return nil, err
        end
      end

      local ok, err = kong.core_cache:safe_set(cache_key, item, shadow)
      if not ok then
        return nil, err
      end

      local global_query_cache_key = dao:cache_key(id, nil, nil, nil, nil, "*")
      local ok, err = kong.core_cache:safe_set(global_query_cache_key, item, shadow)
      if not ok then
        return nil, err
      end

      -- insert individual entry for global query
      table.insert(keys_by_ws["*"], cache_key)

      -- insert individual entry for workspaced query
      if ws_id ~= "" then
        keys_by_ws[ws_id] = keys_by_ws[ws_id] or {}
        local keys = keys_by_ws[ws_id]
        table.insert(keys, cache_key)
      end

      if schema.cache_key then
        local cache_key = dao:cache_key(item)
        ok, err = kong.core_cache:safe_set(cache_key, item, shadow)
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

          local prefix = entity_name .. "|" .. ws_id
          if schema.fields[unique].unique_across_ws then
            prefix = entity_name .. "|"
          end

          local unique_cache_key = prefix .. "|" .. unique .. ":" .. unique_key
          ok, err = kong.core_cache:safe_set(unique_cache_key, item, shadow)
          if not ok then
            return nil, err
          end
        end
      end

      for fname, ref in pairs(foreign_fields) do
        if item[fname] then
          local fschema = kong.db[ref].schema

          local fid = declarative_config.pk_string(fschema, item[fname])

          -- insert paged search entry for global query
          page_for[ref]["*"] = page_for[ref]["*"] or {}
          page_for[ref]["*"][fid] = page_for[ref]["*"][fid] or {}
          table.insert(page_for[ref]["*"][fid], cache_key)

          -- insert paged search entry for workspaced query
          page_for[ref][ws_id] = page_for[ref][ws_id] or {}
          page_for[ref][ws_id][fid] = page_for[ref][ws_id][fid] or {}
          table.insert(page_for[ref][ws_id][fid], cache_key)
        end
      end

      if item.tags then

        local ws = schema.workspaceable and ws_id or ""
        for _, tag_name in ipairs(item.tags) do
          table.insert(tags, tag_name .. "|" .. entity_name .. "|" .. id)

          tags_by_name[tag_name] = tags_by_name[tag_name] or {}
          table.insert(tags_by_name[tag_name], tag_name .. "|" .. entity_name .. "|" .. id)

          taggings[tag_name] = taggings[tag_name] or {}
          taggings[tag_name][ws] = taggings[tag_name][ws] or {}
          taggings[tag_name][ws][cache_key] = true
        end
      end
    end

    for ws_id, keys in pairs(keys_by_ws) do
      local entity_prefix = entity_name .. "|" .. (schema.workspaceable and ws_id or "")

      local ok, err = kong.core_cache:safe_set(entity_prefix .. "|@list", keys, shadow)
      if not ok then
        return nil, err
      end

      for ref, wss in pairs(page_for) do
        local fids = wss[ws_id]
        if fids then
          for fid, entries in pairs(fids) do
            local key = entity_prefix .. "|" .. ref .. "|" .. fid .. "|@list"
            local ok, err = kong.core_cache:safe_set(key, entries, shadow)
            if not ok then
              return nil, err
            end
          end
        end
      end
    end

    -- taggings:admin|services|ws_id|@list -> uuids of services tagged "admin" on workspace ws_id
    for tag_name, workspaces_dict in pairs(taggings) do
      for ws_id, keys_dict in pairs(workspaces_dict) do
        local key = "taggings:" .. tag_name .. "|" .. entity_name .. "|" .. ws_id .. "|@list"

        -- transform the dict into a sorted array
        local arr = {}
        local len = 0
        for id in pairs(keys_dict) do
          len = len + 1
          arr[len] = id
        end
        -- stay consistent with pagination
        table.sort(arr)
        local ok, err = kong.core_cache:safe_set(key, arr, shadow)
        if not ok then
          return nil, err
        end
      end
    end
  end

  for tag_name, tags in pairs(tags_by_name) do
    -- tags:admin|@list -> all tags tagged "admin", regardless of the entity type
    -- each tag is encoded as a string with the format "admin|services|uuid", where uuid is the service uuid
    local key = "tags:" .. tag_name .. "|@list"
    local ok, err = kong.core_cache:safe_set(key, tags, shadow)
    if not ok then
      return nil, err
    end
  end

  -- tags||@list -> all tags, with no distinction of tag name or entity type.
  -- each tag is encoded as a string with the format "admin|services|uuid", where uuid is the service uuid
  local ok, err = kong.core_cache:safe_set("tags||@list", tags, shadow)
  if not ok then
    return nil, err
  end

  local ok, err = ngx.shared.kong:safe_set(DECLARATIVE_HASH_KEY, hash or true)
  if not ok then
    return nil, "failed to set " .. DECLARATIVE_HASH_KEY .. " in shm: " .. err
  end


  kong.default_workspace = default_workspace
  return true, nil, default_workspace
end


do
  local DECLARATIVE_PAGE_KEY = constants.DECLARATIVE_PAGE_KEY

  function declarative.load_into_cache_with_events(entities, meta, hash)
    if ngx.worker.exiting() then
      return nil, "exiting"
    end

    local ok, err = declarative.try_lock()
    if not ok then
      if err == "exists" then
        local ttl = math.min(ngx.shared.kong:ttl(DECLARATIVE_LOCK_KEY), 10)
        return nil, "busy", ttl
      end

      ngx.shared.kong:delete(DECLARATIVE_LOCK_KEY)
      return nil, err
    end

    -- ensure any previous update finished (we're flipped to the latest page)
    ok, err = kong.worker_events.poll()
    if not ok then
      ngx.shared.kong:delete(DECLARATIVE_LOCK_KEY)
      return nil, err
    end

    if SUBSYS == "http" and #kong.configuration.stream_listeners > 0 and
       ngx.get_phase() ~= "init_worker"
    then
      -- update stream if necessary
      -- TODO: remove this once shdict can be shared between subsystems

      local sock = ngx_socket_tcp()
      ok, err = sock:connect("unix:" .. PREFIX .. "/stream_config.sock")
      if not ok then
        ngx.shared.kong:delete(DECLARATIVE_LOCK_KEY)
        return nil, err
      end

      local json = cjson.encode({ entities, meta, hash, })
      local bytes
      bytes, err = sock:send(json)
      sock:close()

      if not bytes then
        ngx.shared.kong:delete(DECLARATIVE_LOCK_KEY)
        return nil, err
      end

      assert(bytes == #json, "incomplete config sent to the stream subsystem")
    end

    if ngx.worker.exiting() then
      ngx.shared.kong:delete(DECLARATIVE_LOCK_KEY)
      return nil, "exiting"
    end

    local default_ws
    ok, err, default_ws = declarative.load_into_cache(entities, meta, hash, SHADOW)
    if ok then
      ok, err = kong.worker_events.post("declarative", "flip_config", default_ws)
      if ok ~= "done" then
        ngx.shared.kong:delete(DECLARATIVE_LOCK_KEY)
        return nil, "failed to flip declarative config cache pages: " .. (err or ok)
      end

    else
      ngx.shared.kong:delete(DECLARATIVE_LOCK_KEY)
      return nil, err
    end

    ok, err = ngx.shared.kong:set(DECLARATIVE_PAGE_KEY, kong.cache:get_page())
    if not ok then
      ngx.shared.kong:delete(DECLARATIVE_LOCK_KEY)
      return nil, "failed to persist cache page number: " .. err
    end

    if ngx.worker.exiting() then
      ngx.shared.kong:delete(DECLARATIVE_LOCK_KEY)
      return nil, "exiting"
    end

    local sleep_left = DECLARATIVE_LOCK_TTL
    local sleep_time = 0.0375

    while sleep_left > 0 do
      local flips = ngx.shared.kong:get(DECLARATIVE_LOCK_KEY)
      if flips == nil or flips >= WORKER_COUNT then
        break
      end

      sleep_time = sleep_time * 2
      if sleep_time > sleep_left then
        sleep_time = sleep_left
      end

      ngx.sleep(sleep_time)

      if ngx.worker.exiting() then
        ngx.shared.kong:delete(DECLARATIVE_LOCK_KEY)
        return nil, "exiting"
      end

      sleep_left = sleep_left - sleep_time
    end

    ngx.shared.kong:delete(DECLARATIVE_LOCK_KEY)

    if sleep_left <= 0 then
      return nil, "timeout"
    end

    return true
  end
end


-- prevent POST /config (declarative.load_into_cache_with_events eary-exits)
-- only "succeeds" the first time it gets called.
-- successive calls return nil, "exists"
function declarative.try_lock()
  return ngx.shared.kong:add(DECLARATIVE_LOCK_KEY, 0, DECLARATIVE_LOCK_TTL)
end


-- increments the counter inside the lock - each worker does this while reading new declarative config
-- can (is expected to) be called multiple times, suceeding every time
function declarative.lock()
  return ngx.shared.kong:incr(DECLARATIVE_LOCK_KEY, 1, 0, DECLARATIVE_LOCK_TTL)
end


-- prevent POST, but release if all workers have finished updating
function declarative.try_unlock()
  local kong_shm = ngx.shared.kong
  if kong_shm:get(DECLARATIVE_LOCK_KEY) then
    local count = kong_shm:incr(DECLARATIVE_LOCK_KEY, 1)
    if count and count >= WORKER_COUNT then
      kong_shm:delete(DECLARATIVE_LOCK_KEY)
    end
  end
end


function declarative.sanitize_output(entities)
  entities.workspaces = nil

  for _, s in pairs(entities) do -- set of entities
    for _, e in pairs(s) do -- individual entity
      e.ws_id = nil
    end
  end
end


return declarative
