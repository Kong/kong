local lmdb = require("resty.lmdb")
local txn = require("resty.lmdb.transaction")
local constants = require("kong.constants")
local workspaces = require("kong.workspaces")
local cycle_aware_deep_copy = require("kong.tools.table").cycle_aware_deep_copy
local declarative_config = require("kong.db.schema.others.declarative_config")
local concurrency = require("kong.concurrency")


local yield = require("kong.tools.yield").yield
local marshall = require("kong.db.declarative.marshaller").marshall
local schema_topological_sort = require("kong.db.schema.topological_sort")
local nkeys = require("table.nkeys")
local sha256_hex = require("kong.tools.sha256").sha256_hex
local pk_string = declarative_config.pk_string
local EMPTY = require("kong.tools.table").EMPTY

local assert = assert
local type = type
local pairs = pairs
local insert = table.insert
local string_format = string.format
local null = ngx.null
local get_phase = ngx.get_phase
local get_workspace_id = workspaces.get_workspace_id


local DECLARATIVE_HASH_KEY = constants.DECLARATIVE_HASH_KEY
local DECLARATIVE_EMPTY_CONFIG_HASH = constants.DECLARATIVE_EMPTY_CONFIG_HASH
local DECLARATIVE_DEFAULT_WORKSPACE_KEY = constants.DECLARATIVE_DEFAULT_WORKSPACE_KEY


local GLOBAL_WORKSPACE_TAG = "*"
local UNINIT_WORKSPACE_ID = "00000000-0000-0000-0000-000000000000"


local function get_default_workspace()
  -- in init phase we can not access lmdb
  if kong.default_workspace == UNINIT_WORKSPACE_ID and
     get_phase() ~= "init"
  then
    local res = kong.db.workspaces:select_by_name("default")
    kong.default_workspace = assert(res and res.id)
  end

  return kong.default_workspace
end


-- Generates the appropriate workspace ID for current operating context
-- depends on schema settings
--
-- Non-workspaceable entities are always placed under the "default"
-- workspace
--
-- If the query explicitly set options.workspace == null, then all
-- workspaces shall be used
--
-- If the query explicitly set options.workspace == "some UUID", then
-- it will be returned
--
-- Otherwise, the current workspace ID will be returned
local function workspace_id(schema, options)
  if not schema.workspaceable then
    return get_default_workspace()
  end

  -- options.workspace does not exist
  if not options or not options.workspace then
    return get_workspace_id()
  end

  if options.workspace == null then
    return GLOBAL_WORKSPACE_TAG
  end

  -- options.workspace is a UUID
  return options.workspace
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
      entity = cycle_aware_deep_copy(entity)
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


--- Remove all nulls from declarative config.
-- Declarative config is a huge table. Use iteration
-- instead of recursion to improve performance.
local function remove_nulls(tbl)
  local stk = { tbl }
  local n = #stk

  local cur
  while n > 0 do
    cur = stk[n]

    stk[n] = nil
    n = n - 1

    if type(cur) == "table" then
      for k, v in pairs(cur) do
        if v == null then
          cur[k] = nil

        elseif type(v) == "table" then
          n = n + 1
          stk[n] = v
        end
      end
    end
  end

  return tbl
end


--- Restore all nulls for declarative config.
-- Declarative config is a huge table. Use iteration
-- instead of recursion to improve performance.
local function restore_nulls(original_tbl, transformed_tbl)
  local o_stk = { original_tbl }
  local o_n = #o_stk

  local t_stk = { transformed_tbl }
  local t_n = #t_stk

  local o_cur, t_cur
  while o_n > 0 and o_n == t_n do
    o_cur = o_stk[o_n]
    o_stk[o_n] = nil
    o_n = o_n - 1

    t_cur = t_stk[t_n]
    t_stk[t_n] = nil
    t_n = t_n - 1

    for k, v in pairs(o_cur) do
      if v == null and
         t_cur[k] == nil
      then
        t_cur[k] = null

      elseif type(v) == "table" and
             type(t_cur[k]) == "table"
      then
        o_n = o_n + 1
        o_stk[o_n] = v

        t_n = t_n + 1
        t_stk[t_n] = t_cur[k]
      end
    end
  end

  return transformed_tbl
end


local function get_current_hash()
  return lmdb.get(DECLARATIVE_HASH_KEY)
end


local function find_ws(entities, name)
  for _, v in pairs(entities.workspaces or EMPTY) do
    if v.name == name then
      return v.id
    end
  end
end


local function unique_field_key(schema_name, ws_id, field, value)
  return string_format("%s|%s|%s|%s", schema_name, ws_id, field, sha256_hex(value))
end


local function foreign_field_key_prefix(schema_name, ws_id, field, foreign_id)
  return string_format("%s|%s|%s|%s|", schema_name, ws_id, field, foreign_id)
end


local function foreign_field_key(schema_name, ws_id, field, foreign_id, pk)
  return foreign_field_key_prefix(schema_name, ws_id, field, foreign_id) .. pk
end

local function item_key_prefix(schema_name, ws_id)
  return string_format("%s|%s|*|", schema_name, ws_id)
end


local function item_key(schema_name, ws_id, pk_str)
  return item_key_prefix(schema_name, ws_id) .. pk_str
end


local function config_is_empty(entities)
  -- empty configuration has no entries other than workspaces
  return entities.workspaces and nkeys(entities) == 1
end


-- common implementation for
-- insert_entity_for_txn() and delete_entity_for_txn()
local function _set_entity_for_txn(t, entity_name, item, options, is_delete)
  local dao = kong.db[entity_name]
  local schema = dao.schema
  local pk = pk_string(schema, item)

  -- If the item belongs to a specific workspace,
  -- use it directly without using the default one.
  local ws_id = item.ws_id or workspace_id(schema, options)

  local itm_key = item_key(entity_name, ws_id, pk)

  -- if we are deleting, item_value and idx_value should be nil
  local itm_value, idx_value

  -- if we are inserting or updating
  -- itm_value is serialized entity
  -- idx_value is the lmdb item_key
  if not is_delete then
    local err

    -- serialize item with possible nulls
    itm_value, err = marshall(item)
    if not itm_value then
      return nil, err
    end

    idx_value = itm_key
  end

  -- store serialized entity into lmdb
  t:set(itm_key, itm_value)

  -- for global query
  local global_key = item_key(entity_name, GLOBAL_WORKSPACE_TAG, pk)
  t:set(global_key, idx_value)

  -- select_by_cache_key
  if schema.cache_key then
    local cache_key = dao:cache_key(item)
    -- The second parameter (ws_id) is a placeholder here, because the cache_key
    -- is already unique globally.
    local key = unique_field_key(entity_name, get_default_workspace(),
                                 "cache_key", cache_key)
    -- store item_key or nil into lmdb
    t:set(key, idx_value)
  end

  for fname, fdata in schema:each_field() do
    local is_foreign = fdata.type == "foreign"
    local fdata_reference = fdata.reference
    local value = item[fname]
    -- avoid overriding the outer ws_id
    local field_ws_id = fdata.unique_across_ws and kong.default_workspace or ws_id

    -- value may be null, we should skip it
    if not value or value == null then
      goto continue
    end

    -- value should be a string or table

    local value_str

    if fdata.unique then
      -- unique and not a foreign key, or is a foreign key, but non-composite
      -- see: validate_foreign_key_is_single_primary_key, composite foreign
      -- key is currently unsupported by the DAO
      if type(value) == "table" then
        assert(is_foreign)
        value_str = pk_string(kong.db[fdata_reference].schema, value)
      end

      for _, wid in ipairs {field_ws_id, GLOBAL_WORKSPACE_TAG} do
        local key = unique_field_key(entity_name, wid, fname, value_str or value)

        -- store item_key or nil into lmdb
        t:set(key, idx_value)
      end
    end

    if is_foreign then
      -- is foreign, generate page_for_foreign_field indexes
      assert(type(value) == "table")

      value_str = pk_string(kong.db[fdata_reference].schema, value)

      for _, wid in ipairs {field_ws_id, GLOBAL_WORKSPACE_TAG} do
        local key = foreign_field_key(entity_name, wid, fname, value_str, pk)

        -- store item_key or nil into lmdb
        t:set(key, idx_value)
      end
    end

    ::continue::
  end -- for fname, fdata in schema:each_field()

  return true
end


-- Serialize and set keys for a single validated entity into
-- the provided LMDB txn object, this operation is only safe
-- is the entity does not already exist inside the LMDB database
--
-- The actual item key is: <entity_name>|<ws_id>|*|<pk_string>
--
-- This function sets the following:
--
-- * <entity_name>|<ws_id>|*|<pk_string> => serialized item
-- * <entity_name>|*|*|<pk_string> => actual item key
--
-- * <entity_name>|<ws_id>|<unique_field_name>|sha256(field_value) => actual item key
-- * <entity_name>|*|<unique_field_name>|sha256(field_value) => actual item key
--
-- * <entity_name>|<ws_id>|<foreign_field_name>|<foreign_key>|<pk_string> => actual item key
-- * <entity_name>|*|<foreign_field_name>|<foreign_key>|<pk_string> => actual item key
--
-- DO NOT touch `item`, or else the entity will be changed
local function insert_entity_for_txn(t, entity_name, item, options)
  return _set_entity_for_txn(t, entity_name, item, options, false)
end


-- Serialize and remove keys for a single validated entity into
-- the provided LMDB txn object, this operation is safe whether the provided
-- entity exists inside LMDB or not, but the provided entity must contains the
-- correct field value so indexes can be deleted correctly
local function delete_entity_for_txn(t, entity_name, item, options)
  return _set_entity_for_txn(t, entity_name, item, options, true)
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

  -- set it for insert_entity_for_txn()
  kong.default_workspace = default_workspace_id

  if not hash or hash == "" or config_is_empty(entities) then
    hash = DECLARATIVE_EMPTY_CONFIG_HASH
  end

  local db = kong.db

  local t = txn.begin(512)
  t:db_drop(false)

  local phase = get_phase()

  for entity_name, items in pairs(entities) do
    yield(true, phase)

    local dao = db[entity_name]
    if not dao then
      return nil, "unknown entity: " .. entity_name
    end
    local schema = dao.schema

    for _, item in pairs(items) do
      if not schema.workspaceable or item.ws_id == null or item.ws_id == nil then
        item.ws_id = default_workspace_id
      end

      assert(type(item.ws_id) == "string")

      if should_transform and schema:has_transformations(item) then
        local transformed_item = cycle_aware_deep_copy(item)
        remove_nulls(transformed_item)

        local err
        transformed_item, err = schema:transform(transformed_item)
        if not transformed_item then
          return nil, err
        end

        item = restore_nulls(item, transformed_item)
        if not item then
          return nil, err
        end
      end

      -- nil means no extra options
      local res, err = insert_entity_for_txn(t, entity_name, item, nil)
      if not res then
        return nil, err
      end
    end -- for for _, item
  end -- for entity_name, items

  t:set(DECLARATIVE_HASH_KEY, hash)
  t:set(DECLARATIVE_DEFAULT_WORKSPACE_KEY, default_workspace_id)

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

  load_into_cache_with_events = function(entities, meta, hash, hashes)
    local ok, err, ttl = concurrency.with_worker_mutex({
      name = DECLARATIVE_LOCK_KEY,
      timeout = 0,
      exptime = DECLARATIVE_LOCK_TTL,
    }, function()
      return load_into_cache_with_events_no_lock(entities, meta, hash, hashes)
    end)

    if not ok then
      if err == "timeout" then
        ttl = ttl or DECLARATIVE_RETRY_TTL_MAX
        local retry_after = min(ttl, DECLARATIVE_RETRY_TTL_MAX)
        return nil, "busy", retry_after
      end

      return nil, err
    end

    return ok, err
  end
end


return {
  get_current_hash = get_current_hash,
  unique_field_key = unique_field_key,
  foreign_field_key = foreign_field_key,
  foreign_field_key_prefix = foreign_field_key_prefix,
  item_key = item_key,
  item_key_prefix = item_key_prefix,
  workspace_id = workspace_id,

  load_into_db = load_into_db,
  load_into_cache = load_into_cache,
  load_into_cache_with_events = load_into_cache_with_events,
  insert_entity_for_txn = insert_entity_for_txn,
  delete_entity_for_txn = delete_entity_for_txn,
}
