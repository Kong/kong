local declarative_config = require "kong.db.schema.others.declarative_config"
local schema_topological_sort = require "kong.db.schema.topological_sort"
local workspaces = require "kong.workspaces"
local pl_file = require "pl.file"
local lyaml = require "lyaml"
local cjson = require "cjson.safe"
local tablex = require "pl.tablex"
local constants = require "kong.constants"
local txn = require "resty.lmdb.transaction"
local lmdb = require "resty.lmdb"

local setmetatable = setmetatable
local loadstring = loadstring
local tostring = tostring
local exiting = ngx.worker.exiting
local setfenv = setfenv
local io_open = io.open
local insert = table.insert
local concat = table.concat
local assert = assert
local error = error
local pcall = pcall
local sort = table.sort
local type = type
local next = next
local deepcopy = tablex.deepcopy
local null = ngx.null
local md5 = ngx.md5
local pairs = pairs
local ngx_socket_tcp = ngx.socket.tcp
local yield = require("kong.tools.utils").yield
local marshall = require("kong.db.declarative.marshaller").marshall
local min = math.min


local REMOVE_FIRST_LINE_PATTERN = "^[^\n]+\n(.+)$"
local PREFIX = ngx.config.prefix()
local SUBSYS = ngx.config.subsystem
local DECLARATIVE_HASH_KEY = constants.DECLARATIVE_HASH_KEY
local DECLARATIVE_EMPTY_CONFIG_HASH = constants.DECLARATIVE_EMPTY_CONFIG_HASH
local GLOBAL_QUERY_OPTS = { nulls = true, workspace = null }


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
      sort(accepted)

      err = "unknown file type: " ..
            tostring(filename) ..
            ". (Accepted types: " ..
            concat(accepted, ", ") .. ")"
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

  yield()

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

  local fd, err = io_open(filename, "w")
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

  local db_workspaces = kong.db.workspaces
  local workspace, err, err_t = db_workspaces:select_by_name(name)
  if err then
    return nil, err, err_t
  end

  if not workspace then
    workspace, err, err_t = db_workspaces:upsert_by_name(name, {
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

  local db = kong.db

  local schemas = {}
  for entity_name in pairs(entities) do
    local entity = db[entity_name]
    if entity then
      insert(schemas, entity.schema)
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

      ok, err, err_t = db[schema.name]:upsert(primary_key, entity, options)
      if not ok then
        return nil, err, err_t
      end
    end
  end

  return true
end


local function export_from_db(emitter, skip_ws, skip_disabled_entities)
  local schemas = {}

  local db = kong.db

  for _, dao in pairs(db.daos) do
    if not (skip_ws and dao.schema.name == "workspaces") then
      insert(schemas, dao.schema)
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

  local disabled_services = {}
  for i = 1, #sorted_schemas do
    local schema = sorted_schemas[i]
    if schema.db_export == false then
      goto continue
    end

    local name = schema.name
    local fks = {}
    for field_name, field in schema:each_field() do
      if field.type == "foreign" then
        insert(fks, field_name)
      end
    end

    local page_size
    if db[name].pagination then
      page_size = db[name].pagination.max_page_size
    end
    for row, err in db[name]:each(page_size, GLOBAL_QUERY_OPTS) do
      if not row then
        kong.log.err(err)
        return nil, err
      end

      -- do not export disabled services and disabled plugins when skip_disabled_entities
      -- as well do not export plugins and routes of dsiabled services
      if skip_disabled_entities and name == "services" and not row.enabled then
        disabled_services[row.id] = true

      elseif skip_disabled_entities and name == "plugins" and not row.enabled then
        goto skip_emit

      else
        for j = 1, #fks do
          local foreign_name = fks[j]
          if type(row[foreign_name]) == "table" then
            local id = row[foreign_name].id
            if id ~= nil then
              if disabled_services[id] then
                goto skip_emit
              end
              row[foreign_name] = id
            end
          end
        end

        emitter:emit_entity(name, row)
      end
      ::skip_emit::
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


function declarative.export_from_db(fd, skip_ws, skip_disabled_entities)
  -- not sure if this really useful for skip_ws,
  -- but I want to allow skip_disabled_entities and would rather have consistent interface
  if skip_ws == nil then
    skip_ws = true
  end

  if skip_disabled_entities == nil then
    skip_disabled_entities = false
  end

  return export_from_db(fd_emitter.new(fd), skip_ws, skip_disabled_entities)
end


local table_emitter = {
  emit_toplevel = function(self, tbl)
    self.out = tbl
  end,

  emit_entity = function(self, entity_name, entity_data)
    if not self.out[entity_name] then
      self.out[entity_name] = { entity_data }
    else
      insert(self.out[entity_name], entity_data)
    end
  end,

  done = function(self)
    return self.out
  end,
}


function table_emitter.new()
  return setmetatable({}, { __index = table_emitter })
end


function declarative.export_config(skip_ws, skip_disabled_entities)
  -- default skip_ws=false and skip_disabled_services=true
  if skip_ws == nil then
    skip_ws = false
  end

  if skip_disabled_entities == nil then
    skip_disabled_entities = true
  end

  return export_from_db(table_emitter.new(), skip_ws, skip_disabled_entities)
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
  return lmdb.get(DECLARATIVE_HASH_KEY)
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
function declarative.load_into_cache(entities, meta, hash)
  -- Array of strings with this format:
  -- "<tag_name>|<entity_name>|<uuid>".
  -- For example, a service tagged "admin" would produce
  -- "admin|services|<the service uuid>"
  local tags = {}
  meta = meta or {}

  local default_workspace = assert(find_default_ws(entities))
  local fallback_workspace = default_workspace

  assert(type(fallback_workspace) == "string")

  if not hash or hash == "" then
    hash = DECLARATIVE_EMPTY_CONFIG_HASH
  end

  -- Keys: tag name, like "admin"
  -- Values: array of encoded tags, similar to the `tags` variable,
  -- but filtered for a given tag
  local tags_by_name = {}

  local db = kong.db

  local t = txn.begin(128)
  t:db_drop(false)

  local transform = meta._transform == nil and true or meta._transform

  for entity_name, items in pairs(entities) do
    yield()

    local dao = db[entity_name]
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
          if #db[fdata.reference].schema.primary_key == 1 then
            insert(uniques, fname)
          end

        else
          insert(uniques, fname)
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

      yield(true)

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

      local item_marshalled, err = marshall(item)
      if not item_marshalled then
        return nil, err
      end

      t:set(cache_key, item_marshalled)

      local global_query_cache_key = dao:cache_key(id, nil, nil, nil, nil, "*")
      t:set(global_query_cache_key, item_marshalled)

      -- insert individual entry for global query
      insert(keys_by_ws["*"], cache_key)

      -- insert individual entry for workspaced query
      if ws_id ~= "" then
        keys_by_ws[ws_id] = keys_by_ws[ws_id] or {}
        local keys = keys_by_ws[ws_id]
        insert(keys, cache_key)
      end

      if schema.cache_key then
        local cache_key = dao:cache_key(item)
        t:set(cache_key, item_marshalled)
      end

      for i = 1, #uniques do
        local unique = uniques[i]
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
          t:set(unique_cache_key, item_marshalled)
        end
      end

      for fname, ref in pairs(foreign_fields) do
        if item[fname] then
          local fschema = db[ref].schema

          local fid = declarative_config.pk_string(fschema, item[fname])

          -- insert paged search entry for global query
          page_for[ref]["*"] = page_for[ref]["*"] or {}
          page_for[ref]["*"][fid] = page_for[ref]["*"][fid] or {}
          insert(page_for[ref]["*"][fid], cache_key)

          -- insert paged search entry for workspaced query
          page_for[ref][ws_id] = page_for[ref][ws_id] or {}
          page_for[ref][ws_id][fid] = page_for[ref][ws_id][fid] or {}
          insert(page_for[ref][ws_id][fid], cache_key)
        end
      end

      local item_tags = item.tags
      if item_tags then
        local ws = schema.workspaceable and ws_id or ""
        for i = 1, #item_tags do
          local tag_name = item_tags[i]
          insert(tags, tag_name .. "|" .. entity_name .. "|" .. id)

          tags_by_name[tag_name] = tags_by_name[tag_name] or {}
          insert(tags_by_name[tag_name], tag_name .. "|" .. entity_name .. "|" .. id)

          taggings[tag_name] = taggings[tag_name] or {}
          taggings[tag_name][ws] = taggings[tag_name][ws] or {}
          taggings[tag_name][ws][cache_key] = true
        end
      end
    end

    for ws_id, keys in pairs(keys_by_ws) do
      local entity_prefix = entity_name .. "|" .. (schema.workspaceable and ws_id or "")

      local keys, err = marshall(keys)
      if not keys then
        return nil, err
      end

      t:set(entity_prefix .. "|@list", keys)

      for ref, wss in pairs(page_for) do
        local fids = wss[ws_id]
        if fids then
          for fid, entries in pairs(fids) do
            local key = entity_prefix .. "|" .. ref .. "|" .. fid .. "|@list"

            local entries, err = marshall(entries)
            if not entries then
              return nil, err
            end

            t:set(key, entries)
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
        sort(arr)

        local arr, err = marshall(arr)
        if not arr then
          return nil, err
        end

        t:set(key, arr)
      end
    end
  end

  for tag_name, tags in pairs(tags_by_name) do
    yield()

    -- tags:admin|@list -> all tags tagged "admin", regardless of the entity type
    -- each tag is encoded as a string with the format "admin|services|uuid", where uuid is the service uuid
    local key = "tags:" .. tag_name .. "|@list"
    local tags, err = marshall(tags)
    if not tags then
      return nil, err
    end

    t:set(key, tags)
  end

  -- tags||@list -> all tags, with no distinction of tag name or entity type.
  -- each tag is encoded as a string with the format "admin|services|uuid", where uuid is the service uuid
  local tags, err = marshall(tags)
  if not tags then
    return nil, err
  end

  t:set("tags||@list", tags)
  t:set(DECLARATIVE_HASH_KEY, hash)

  kong.default_workspace = default_workspace

  local ok, err = t:commit()
  if not ok then
    return nil, err
  end

  kong.core_cache:purge()
  kong.cache:purge()

  return true, nil, default_workspace
end


do
  local function load_into_cache_with_events_no_lock(entities, meta, hash)
    if exiting() then
      return nil, "exiting"
    end

    local worker_events = kong.worker_events

    local ok, err, default_ws = declarative.load_into_cache(entities, meta, hash)
    if ok then
      ok, err = worker_events.post("declarative", "reconfigure", default_ws)
      if ok ~= "done" then
        return nil, "failed to broadcast reconfigure event: " .. (err or ok)
      end

    elseif err:find("MDB_MAP_FULL", nil, true) then
      return nil, "map full"

    else
      return nil, err
    end

    if SUBSYS == "http" and #kong.configuration.stream_listeners > 0 then
      -- update stream if necessary

      local sock = ngx_socket_tcp()
      ok, err = sock:connect("unix:" .. PREFIX .. "/stream_config.sock")
      if not ok then
        return nil, err
      end

      local bytes
      bytes, err = sock:send(default_ws)
      sock:close()

      if not bytes then
        return nil, err
      end

      assert(bytes == #default_ws,
             "incomplete default workspace id sent to the stream subsystem")
    end


    if exiting() then
      return nil, "exiting"
    end

    return true
  end

  -- If it takes more than 60s it is very likely to be an internal error.
  -- However it will be reported as: "failed to broadcast reconfigure event: recursive".
  -- Let's paste the error message here in case someday we try to search it.
  -- Should we handle this case specially?
  local DECLARATIVE_LOCK_TTL = 60
  local DECLARATIVE_RETRY_TTL_MAX = 10
  local DECLARATIVE_LOCK_KEY = "declarative:lock"

  -- make sure no matter which path it exits, we released the lock.
  function declarative.load_into_cache_with_events(entities, meta, hash)
    local kong_shm = ngx.shared.kong

    local ok, err = kong_shm:add(DECLARATIVE_LOCK_KEY, 0, DECLARATIVE_LOCK_TTL)
    if not ok then
      if err == "exists" then
        local ttl = min(kong_shm:ttl(DECLARATIVE_LOCK_KEY), DECLARATIVE_RETRY_TTL_MAX)
        return nil, "busy", ttl
      end

      kong_shm:delete(DECLARATIVE_LOCK_KEY)
      return nil, err
    end

    ok, err = load_into_cache_with_events_no_lock(entities, meta, hash)

    kong_shm:delete(DECLARATIVE_LOCK_KEY)

    return ok, err
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
