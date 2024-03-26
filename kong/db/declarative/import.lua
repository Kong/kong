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

local assert = assert
local sort = table.sort
local type = type
local pairs = pairs
local next = next
local insert = table.insert
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


local function find_default_ws(entities)
  for _, v in pairs(entities.workspaces or {}) do
    if v.name == "default" then
      return v.id
    end
  end
end


local function unique_field_key(schema_name, ws_id, field, value, unique_across_ws)
  if unique_across_ws then
    ws_id = ""
  end

  return schema_name .. "|" .. ws_id .. "|" .. field .. ":" .. value
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
  -- Array of strings with this format:
  -- "<tag_name>|<entity_name>|<uuid>".
  -- For example, a service tagged "admin" would produce
  -- "admin|services|<the service uuid>"
  local tags = {}
  meta = meta or {}

  local default_workspace = assert(find_default_ws(entities))
  local fallback_workspace = default_workspace

  assert(type(fallback_workspace) == "string")

  if not hash or hash == "" or config_is_empty(entities) then
    hash = DECLARATIVE_EMPTY_CONFIG_HASH
  end

  -- Keys: tag name, like "admin"
  -- Values: array of encoded tags, similar to the `tags` variable,
  -- but filtered for a given tag
  local tags_by_name = {}

  local db = kong.db

  local t = txn.begin(128)
  t:db_drop(false)

  local phase = get_phase()
  yield(false, phase)   -- XXX
  local transform = meta._transform == nil and true or meta._transform

  for entity_name, items in pairs(entities) do
    yield(true, phase)

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
      local is_foreign = fdata.type == "foreign"
      local fdata_reference = fdata.reference

      if fdata.unique then
        if is_foreign then
          if #db[fdata_reference].schema.primary_key == 1 then
            insert(uniques, fname)
          end

        else
          insert(uniques, fname)
        end
      end
      if is_foreign then
        page_for[fdata_reference] = {}
        foreign_fields[fname] = fdata_reference
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

      yield(true, phase)

      assert(type(fallback_workspace) == "string")

      local ws_id = ""
      if schema.workspaceable then
        local item_ws_id = item.ws_id
        if item_ws_id == null or item_ws_id == nil then
          item_ws_id = fallback_workspace
        end
        item.ws_id = item_ws_id
        ws_id = item_ws_id
      end

      assert(type(ws_id) == "string")

      local cache_key = dao:cache_key(id, nil, nil, nil, nil, item.ws_id)
      if transform and schema:has_transformations(item) then
        local transformed_item = utils.cycle_aware_deep_copy(item)
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
        local unique_key = item[unique]
        if unique_key and unique_key ~= null then
          if type(unique_key) == "table" then
            local _
            -- this assumes that foreign keys are not composite
            _, unique_key = next(unique_key)
          end

          local key = unique_field_key(entity_name, ws_id, unique, unique_key,
                                       schema.fields[unique].unique_across_ws)

          t:set(key, item_marshalled)
        end
      end

      for fname, ref in pairs(foreign_fields) do
        local item_fname = item[fname]
        if item_fname and item_fname ~= null then
          local fschema = db[ref].schema

          local fid = declarative_config.pk_string(fschema, item_fname)

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
      if item_tags and item_tags ~= null then
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
    yield(true, phase)

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

  yield(false, phase)

  return true, nil, default_workspace
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
  load_into_cache_with_events = function(entities, meta, hash, hashes)
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

    kong_shm:delete(DECLARATIVE_LOCK_KEY)

    return ok, err
  end
end


return {
  get_current_hash = get_current_hash,
  unique_field_key = unique_field_key,

  load_into_db = load_into_db,
  load_into_cache = load_into_cache,
  load_into_cache_with_events = load_into_cache_with_events,
}
