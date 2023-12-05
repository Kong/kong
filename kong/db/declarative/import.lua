local lmdb = require("resty.lmdb")
local txn = require("resty.lmdb.transaction")
local constants = require("kong.constants")
local workspaces = require("kong.workspaces")
local utils = require("kong.tools.utils")
local declarative_config = require("kong.db.schema.others.declarative_config")


local yield = require("kong.tools.yield").yield
local marshall = require("kong.db.declarative.marshaller").marshall
local schema_topological_sort = require("kong.db.schema.topological_sort")
local nkeys = require("table.nkeys")
local sha256_hex = require("kong.tools.utils").sha256_hex
local pk_string = declarative_config.pk_string

local assert = assert
local sort = table.sort
local type = type
local pairs = pairs
local next = next
local insert = table.insert
local string_format = string.format
local null = ngx.null
local get_phase = ngx.get_phase


local DECLARATIVE_HASH_KEY = constants.DECLARATIVE_HASH_KEY
local DECLARATIVE_EMPTY_CONFIG_HASH = constants.DECLARATIVE_EMPTY_CONFIG_HASH


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


local function load_into_db(entities, meta)
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

  for i = 1, #sorted_schemas do
    local schema = sorted_schemas[i]
    local schema_name = schema.name

    local primary_key, ok, err, err_t
    for _, entity in pairs(entities[schema_name]) do
      entity = utils.cycle_aware_deep_copy(entity)
      entity._tags = nil
      entity.ws_id = nil

      primary_key = schema:extract_pk_values(entity)

      ok, err, err_t = db[schema_name]:upsert(primary_key, entity, options)
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


local function get_current_hash()
  return lmdb.get(DECLARATIVE_HASH_KEY)
end


local function find_ws(entities, name)
  for _, v in pairs(entities.workspaces or {}) do
    if v.name == name then
      return v.id
    end
  end
end


local function unique_field_key(schema_name, ws_id, field, value)
  return string_format("%s|%s|%s|%s", schema_name, ws_id, field, sha256_hex(value))
end


local function foreign_field_key(schema_name, ws_id, field, foreign_id, pk)
  if pk then
    return string_format("%s|%s|%s|%s|%s", schema_name, ws_id, field, foreign_id, pk)
  end

  return string_format("%s|%s|%s|%s|", schema_name, ws_id, field, foreign_id)
end


local function config_is_empty(entities)
  -- empty configuration has no entries other than workspaces
  return entities.workspaces and nkeys(entities) == 1
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
--     _format_version: "3.0",
--     _transform: true,
--   }
local function load_into_cache(entities, meta, hash)
  local default_workspace_id = assert(find_ws(entities, "default"))
  local should_transform = meta._transform == nil and true or meta._transform

  assert(type(default_workspace_id) == "string")

  if not hash or hash == "" or config_is_empty(entities) then
    hash = DECLARATIVE_EMPTY_CONFIG_HASH
  end

  local t = txn.begin(512)
  t:db_drop(false)

  for entity_name, items in pairs(entities) do
    local dao = kong.db[entity_name]
    if not dao then
      return nil, "unknown entity: " .. entity_name
    end
    local schema = dao.schema

    for id, item in pairs(items) do
      local ws_id = default_workspace_id

      if schema.workspaceable and item.ws_id == null or item.ws_id == nil then
        item.ws_id = ws_id
      end

      assert(type(ws_id) == "string")

      local pk = pk_string(schema, item)

      local item_key = string_format("%s|%s|*|%s", entity_name, ws_id, pk)

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

      t:set(item_key, item_marshalled)

      -- select_by_cache_key
      if schema.cache_key then
        local cache_key = dao:cache_key(item)
        local key = unique_field_key(entity_name, ws_id, "cache_key", cache_key)
        t:set(key, item_key)
      end

      for fname, fdata in schema:each_field() do
        local is_foreign = fdata.type == "foreign"
        local fdata_reference = fdata.reference
        local value = item[fname]

        if value then
          if fdata.unique then
            -- unique and not a foreign key, or is a foreign key, but non-composite
            if type(value) == "table" then
              assert(is_foreign)
              value = pk_string(kong.db[fdata_reference].schema, value)
            end

            if fdata.unique_across_ws then
              ws_id = default_workspace_id
            end

            local key = unique_field_key(entity_name, ws_id, fname, value)
            t:set(key, item_key)

          elseif is_foreign then
            -- not unique and is foreign, generate page_for_foo indexes
            assert(type(value) == "table")
            value = pk_string(kong.db[fdata_reference].schema, value)

            local key = foreign_field_key(entity_name, ws_id, fname, value, pk)
            t:set(key, item_key)
          end
        end
      end
    end
  end

  t:set(DECLARATIVE_HASH_KEY, hash)

  kong.default_workspace = default_workspace_id

  local ok, err = t:commit()
  if not ok then
    return nil, err
  end

  kong.core_cache:purge()
  kong.cache:purge()

  return true, nil, default_workspace_id
end


local load_into_cache_with_events
do
  local events = require("kong.runloop.events")

  local md5 = ngx.md5
  local min = math.min

  local exiting = ngx.worker.exiting

  local function load_into_cache_with_events_no_lock(entities, meta, hash, hashes)
    if exiting() then
      return nil, "exiting"
    end

    local ok, err, default_ws = load_into_cache(entities, meta, hash)
    if not ok then
      if err:find("MDB_MAP_FULL", nil, true) then
        return nil, "map full"
      end

      return nil, err
    end

    local router_hash
    local plugins_hash
    local balancer_hash

    if hashes then
      if hashes.routes ~= DECLARATIVE_EMPTY_CONFIG_HASH then
        router_hash = md5(hashes.services .. hashes.routes)
      else
        router_hash = DECLARATIVE_EMPTY_CONFIG_HASH
      end

      plugins_hash = hashes.plugins

      local upstreams_hash = hashes.upstreams
      local targets_hash   = hashes.targets
      if upstreams_hash ~= DECLARATIVE_EMPTY_CONFIG_HASH or
         targets_hash   ~= DECLARATIVE_EMPTY_CONFIG_HASH
      then
        balancer_hash = md5(upstreams_hash .. targets_hash)
      else
        balancer_hash = DECLARATIVE_EMPTY_CONFIG_HASH
      end
    end

    local reconfigure_data = {
      default_ws,
      router_hash,
      plugins_hash,
      balancer_hash,
    }

    ok, err = events.declarative_reconfigure_notify(reconfigure_data)
    if not ok then
      return nil, err
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
  load_into_cache_with_events = function(entities, meta, hash, hashes, transaction_id)
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

    ok, err = load_into_cache_with_events_no_lock(entities, meta, hash, hashes)

    if ok and transaction_id then
      ok, err = kong_shm:set("declarative:current_transaction_id", transaction_id)
    end

    kong_shm:delete(DECLARATIVE_LOCK_KEY)

    return ok, err
  end
end


return {
  get_current_hash = get_current_hash,
  unique_field_key = unique_field_key,
  foreign_field_key = foreign_field_key,

  load_into_db = load_into_db,
  load_into_cache = load_into_cache,
  load_into_cache_with_events = load_into_cache_with_events,
}
