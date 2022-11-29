local _M = {}
--local _MT = { __index = _M, }

local utils = require "kong.tools.utils"

local assert = assert
local pairs = pairs
local ipairs = ipairs
local tonumber = tonumber
local type = type
local fmt = string.format
local tb_insert = table.insert
local null = ngx.null
local encode_base64 = ngx.encode_base64
local sha256 = utils.sha256_hex
local marshall = require("kong.db.declarative.marshaller").marshall
local unmarshall = require("kong.db.declarative.marshaller").unmarshall


local current_version

local uniques = {}
local foreigns = {}

-- generate from schemas
local cascade_deleting_schemas = {
  upstreams = { "targets", },
  consumers = { "plugins", },
  routes = { "plugins", },
  services = { "plugins", },
}

-- 1e8ff358-fbba-4f32-ac9b-9f896c02b2d8
local function get_ws_id(schema, entity)
  if not schema.workspaceable then
    return ""
  end

  local ws_id = entity.ws_id

  if ws_id == null or ws_id == nil then
    ws_id = kong.default_workspace
    entity.ws_id = ws_id
  end

  return ws_id
end

-- upstreams:37add863-a3e4-4fcb-9784-bf1d43befdfa:::::1e8ff358-fbba-4f32-ac9b-9f896c02b2d8
local function gen_cache_key(dao, schema, entity)
  local ws_id = get_ws_id(schema, entity)

  local cache_key = dao:cache_key(entity.id, nil, nil, nil, nil, ws_id)

  return cache_key
end

-- upstreams:37add863-a3e4-4fcb-9784-bf1d43befdfa:::::*
local function gen_global_cache_key(dao, entity)
  local ws_id = "*"

  local cache_key = dao:cache_key(entity.id, nil, nil, nil, nil, ws_id)

  return cache_key
end

-- targets:37add863-a3e4-4fcb-9784-bf1d43befdfa:127.0.0.1:8081::::1e8ff358-fbba-4f32-ac9b-9f896c02b2d8
local function gen_schema_cache_key(dao, schema, entity)
  if not schema.cache_key then
    return nil
  end

  local cache_key = dao:cache_key(entity)

  return cache_key
end

-- upstreams|1e8ff358-fbba-4f32-ac9b-9f896c02b2d8|name:9aa44d94160d95b7ebeaa1e6540ffb68379a23cd4ee2f6a0ab7624a7b2dd6623
local function unique_field_key(schema_name, ws_id, field, value, unique_across_ws)
  if unique_across_ws then
    ws_id = ""
  end

  -- LMDB imposes a default limit of 511 for keys, but the length of our unique
  -- value might be unbounded, so we'll use a checksum instead of the raw value
  value = sha256(value)

  return schema_name .. "|" .. ws_id .. "|" .. field .. ":" .. value
end

-- may have many unique_keys
local function gen_unique_cache_key(schema, entity)
  local db = kong.db
  local schema_name = schema.name

  local unique_fields = uniques[schema_name]
  if not unique_fields then
    unique_fields = {}

    for fname, fdata in schema:each_field() do
      local is_foreign = fdata.type == "foreign"
      local fdata_reference = fdata.reference

      if fdata.unique then
        if is_foreign then
          if #db[fdata_reference].schema.primary_key == 1 then
            tb_insert(unique_fields, fname)
          end

        else
          tb_insert(unique_fields, fname)
        end
      end
    end -- for schema:each_field()

    uniques[schema_name] = unique_fields
  end

  local ws_id = get_ws_id(schema, entity)

  local keys = {}
  for i = 1, #unique_fields do
    local unique_field = unique_fields[i]
    local unique_key = entity[unique_field]
    if unique_key then
      if type(unique_key) == "table" then
        local _
        -- this assumes that foreign keys are not composite
        _, unique_key = next(unique_key)
      end

      local key = unique_field_key(schema.name, ws_id, unique_field, unique_key,
                                   schema.fields[unique_field].unique_across_ws)

      tb_insert(keys, key)
    end
  end

  return keys
end

-- upstreams|1e8ff358-fbba-4f32-ac9b-9f896c02b2d8|@list
-- upstreams|*|@list
local function gen_workspace_key(schema, entity)
  local keys = {}
  local schema_name = schema.name

  if not schema.workspaceable then
    tb_insert(keys, schema_name .. "||@list")
    return keys
  end

  local ws_id = get_ws_id(schema, entity)

  tb_insert(keys, schema_name .. "|" .. ws_id .. "|@list")
  tb_insert(keys, schema_name .. "|*|@list")

  return keys
end

-- targets|1e8ff358-fbba-4f32-ac9b-9f896c02b2d8|upstreams|37add863-a3e4-4fcb-9784-bf1d43befdfa|@list
-- targets|*|upstreams|37add863-a3e4-4fcb-9784-bf1d43befdfa|@list
local function gen_foreign_key(schema, entity)
  local schema_name = schema.name

  local foreign_fields = foreigns[schema_name]

  if not foreign_fields then
    foreign_fields = {}
    for fname, fdata in schema:each_field() do
      local is_foreign = fdata.type == "foreign"
      local fdata_reference = fdata.reference

      if is_foreign then
        foreign_fields[fname] = fdata_reference
      end
    end
    foreigns[schema_name] = foreign_fields
  end

  local ws_ids = { "*", get_ws_id(schema, entity) }

  local keys = {}
  for name, ref in pairs(foreign_fields) do
    ngx.log(ngx.ERR, "xxx name = ", name, " ref = ", ref)
    local fid = entity[name] and entity[name].id
    if not fid then
      goto continue
    end

    for _, ws_id in ipairs(ws_ids) do
      local key = schema_name .. "|" .. ws_id .. "|" .. ref .. "|" ..
                  fid .. "|@list"
      tb_insert(keys, key)
    end

    ::continue::
  end

  return keys
end

-- base64 for inserting into postgres
local function get_marshall_value(obj)
  local value = marshall(obj)
  --ngx.log(ngx.ERR, "xxx value size = ", #value)

  return encode_base64(value)
end

local function get_revision()
  local connector = kong.db.connector

  local sql = "select nextval('cache_revision');"

  local res, err = connector:query(sql)
  if not res then
  ngx.log(ngx.ERR, "xxx err = ", err)
    return nil, err
  end

  --ngx.log(ngx.ERR, "xxx revison = ", require("inspect")(res))
  --return tonumber(res[1].nextval)
  current_version = tonumber(res[1].nextval)

  return current_version
end


local upsert_stmt = "insert into cache_entries(revision, key, value) " ..
                    "values(%d, '%s', decode('%s', 'base64')) " ..
                    "ON CONFLICT (key) " ..
                    "DO UPDATE " ..
                    "  SET revision = EXCLUDED.revision, value = EXCLUDED.value"

local del_stmt = "delete from cache_entries " ..
                 "where key='%s'"

local insert_changs_stmt = "insert into cache_changes(revision, key, value, event) " ..
                           "values(%d, '%s', decode('%s', 'base64'), %d)"


-- key: routes|*|@list
-- result may be nil or empty table
local function query_list_value(connector, key)
  local sel_stmt = "select value from cache_entries " ..
                   "where key='%s'"
  local sql = fmt(sel_stmt, key)
    ngx.log(ngx.ERR, "xxx sql = ", sql)
  local res, err = connector:query(sql)
  if not res then
    ngx.log(ngx.ERR, "xxx err = ", err)
    return nil, err
  end

  local value = res and res[1] and res[1].value

  return value
end

local NIL_MARSHALL_VALUE = get_marshall_value("")

-- event: 0=>reserved, 1=>create, 2=>update 3=>delete
local function insert_into_changes(connector, revision, key, value, event)
  assert(type(key) == "string")

  -- nil => delete an entry
  if value == nil then
    value = NIL_MARSHALL_VALUE
  end

  local sql = fmt(insert_changs_stmt,
                  revision, key, value, event)
  local res, err = connector:query(sql)
  if not res then
    return nil, err
  end

  return true
end

-- targets|*|@list
-- targets|5c3275ba-8bc8-4def-86ba-8d79107cc002|@list
-- targets|*|upstreams|94c3a25d-01f3-4da1-be72-79a1715dd120|@list
-- targets|5c3275ba-8bc8-4def-86ba-8d79107cc002|upstreams|94c3a25d-01f3-4da1-be72-79a1715dd120|@list
local function upsert_list_value(connector, list_key, revision, cache_key)

  local value = query_list_value(connector, list_key)

  local res, err

  if value then
    local value = unmarshall(value)
    tb_insert(value, cache_key)
    value = get_marshall_value(value)
    ngx.log(ngx.ERR, "xxx upsert for ", list_key)
    res, err = connector:query(fmt(upsert_stmt, revision, list_key, value))
    --ngx.log(ngx.ERR, "xxx ws_key err = ", err)

    -- 2 => update existed data
    insert_into_changes(connector, revision, list_key, value, 2)

  else

    ngx.log(ngx.ERR, "xxx no value for ", list_key)

    local value = get_marshall_value({cache_key})
    local sql = fmt(upsert_stmt, revision, list_key, value)
    --ngx.log(ngx.ERR, "xxx sql:", sql)
    --ngx.log(ngx.ERR, "xxx cache_key :", cache_key)

    res, err = connector:query(sql)
    --ngx.log(ngx.ERR, "xxx ws_key err = ", err)

    -- 1 => create
    insert_into_changes(connector, revision, list_key, value, 1)
  end
end

local function remove_list_value(connector, list_key, revision, cache_key)

  local value = query_list_value(connector, list_key)

  if not value then
    return
  end

  local res, err

  local list = unmarshall(value)
  --ngx.log(ngx.ERR, "xxx re-arrange list is: ", unpack(list))

  -- remove this cache_key
  local new_list = {}
  for _,v in ipairs(list) do
    if v ~= cache_key then
      tb_insert(new_list, v)
    end
  end

  value = get_marshall_value(new_list)
  ngx.log(ngx.ERR, "xxx delete for ", list_key)
  res, err = connector:query(fmt(upsert_stmt, revision, list_key, value))
  --ngx.log(ngx.ERR, "xxx ws_key err = ", err)

  -- 2 => update existed data
  insert_into_changes(connector, revision, list_key, value, 2)
end

local function delete_key(connector, key, revision)
  local sql = fmt(del_stmt, key)
  ngx.log(ngx.ERR, "xxx delete sql = ", sql)

  local res, err = connector:query(sql)

  -- 3 => delete
  insert_into_changes(connector, revision, key, nil, 3)
end

-- ignore schema clustering_data_planes
function _M.upsert(schema, entity, old_entity)
  -- clustering_data_planes
  if schema.db_export == false then
    return true
  end

  local entity_name = schema.name

  -- for cache_changes table
  local changed_keys = {}

  local connector = kong.db.connector
  ngx.log(ngx.ERR, "xxx insert into cache_entries: ", entity_name)

  local dao = kong.db[entity_name]

  local revision = get_revision()

  local cache_key = gen_cache_key(dao, schema, entity)
  local global_key = gen_global_cache_key(dao, entity)
  local schema_key = gen_schema_cache_key(dao, schema, entity)

  ngx.log(ngx.ERR, "xxx cache_key = ", cache_key)
  ngx.log(ngx.ERR, "xxx schema_key = ", schema_key)

  tb_insert(changed_keys, cache_key)
  tb_insert(changed_keys, global_key)

  if schema_key then
    tb_insert(changed_keys, schema_key)
  end

  local is_create = old_entity == nil

  local value = get_marshall_value(entity)

  local res, err

  for _, key in ipairs(changed_keys) do
    res, err = connector:query(fmt(upsert_stmt, revision, key, value))
    if not res then
      ngx.log(ngx.ERR, "xxx err = ", err)
      return nil, err
    end

    -- insert into cache_changes
    insert_into_changes(connector,
                        revision, key, value, is_create and 1 or 2)
  end

  local unique_keys = gen_unique_cache_key(schema, entity)
  for _, key in ipairs(unique_keys) do
    res, err = connector:query(fmt(upsert_stmt, revision, key, value))

    -- insert into cache_changes
    insert_into_changes(connector,
                        revision, key, value, is_create and 1 or 2)
  end

  if is_create then

    -- workspace key

    local ws_keys = gen_workspace_key(schema, entity)

    for _, key in ipairs(ws_keys) do
      upsert_list_value(connector, key, revision, cache_key)
    end

    -- foreign key
    --ngx.log(ngx.ERR, "xxx = ", require("inspect")(entity))
    local fkeys = gen_foreign_key(schema, entity)

    for _, key in ipairs(fkeys) do
      upsert_list_value(connector, key, revision, cache_key)
    end

    return true
  end   -- is_create

  ngx.log(ngx.ERR, "xxx old entity.ws_id = ", old_entity.ws_id)

  -- update, remove old keys
  local old_schema_key = gen_schema_cache_key(dao, schema, old_entity)
  ngx.log(ngx.ERR, "xxx old_schema_key = ", old_schema_key)
  if old_schema_key ~= schema_key then
    delete_key(connector, old_schema_key, revision)
  end

  local old_unique_keys = gen_unique_cache_key(schema, old_entity)

  for _, key in ipairs(old_unique_keys) do
    ngx.log(ngx.ERR, "xxx old unique key = ", key)
    local exist = false
    for _, k in ipairs(unique_keys) do
      if key == k then
        exist = true
        break
      end
    end

    -- find out old keys then delete them
    if not exist then
      delete_key(connector, key, revision)
    end
  end

  return true
end

function _M.delete(schema, entity)
  -- clustering_data_planes
  if schema.db_export == false then
    return true
  end

  local entity_name = schema.name

  local connector = kong.db.connector
  ngx.log(ngx.ERR, "xxx delete from cache_entries: ", entity_name)

  local dao = kong.db[entity_name]

  local cache_key = gen_cache_key(dao, schema, entity)
  local global_key = gen_global_cache_key(dao, entity)
  local schema_key = gen_schema_cache_key(dao, schema, entity)

  local keys = gen_unique_cache_key(schema, entity)

  tb_insert(keys, cache_key)
  tb_insert(keys, global_key)
  if schema_key then
    tb_insert(keys, schema_key)
  end

  local revision = get_revision()

  local res, err
  for _, key in ipairs(keys) do
    delete_key(connector, key, revision)
  end

  -- workspace key

  local ws_keys = gen_workspace_key(schema, entity)

  for _, key in ipairs(ws_keys) do
    remove_list_value(connector, key, revision, cache_key)
  end

  -- foreign key
  local fkeys = gen_foreign_key(schema, entity)

  for _, key in ipairs(fkeys) do
    remove_list_value(connector, key, revision, cache_key)
  end

  -- cascade delete
  local cascade_deleting = cascade_deleting_schemas[entity_name]
  if not cascade_deleting then
    return true
  end

  -- here we only delete foreign keys
  -- dao will cascade delete other entities
  local ws_ids = { "*", get_ws_id(schema, entity) }

  for _, v in ipairs(cascade_deleting) do
    --local del_schema = kong.db[v].schema

    for _, ws_id in ipairs(ws_ids) do
      local fkey = v .. "|" .. ws_id .. "|" .. entity_name .. "|" ..
                   entity.id .. "|@list"
      delete_key(connector, fkey, revision)
    end

  end

  return true
end

local function begin_transaction(db)
  if db.strategy == "postgres" then
    local ok, err = db.connector:connect("read")
    if not ok then
      return nil, err
    end

    ok, err = db.connector:query("BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;", "read")
    if not ok then
      return nil, err
    end
  end

  return true
end


local function end_transaction(db)
  if db.strategy == "postgres" then
    -- just finish up the read-only transaction,
    -- either COMMIT or ROLLBACK is fine.
    db.connector:query("ROLLBACK;", "read")
    db.connector:setkeepalive()
  end
end


function _M.export_config(skip_ws, skip_disabled_entities)
  -- default skip_ws=false and skip_disabled_services=true
  if skip_ws == nil then
    skip_ws = false
  end

  if skip_disabled_entities == nil then
    skip_disabled_entities = true
  end

  -- TODO: disabled_services

  local db = kong.db

  local ok, err = begin_transaction(db)
  if not ok then
    return nil, err
  end

  -- TODO: query by page
  local export_stmt = "select revision, key, value " ..
               "from cache_entries;"

  local res, err = db.connector:query(export_stmt)
  if not res then
    ngx.log(ngx.ERR, "xxx err = ", err)
    end_transaction(db)
    return nil, err
  end

  end_transaction(db)

  return res
end

local function get_first_changed_revision()
  local connector = kong.db.connector

  local sql = "SELECT revision FROM cache_changes limit 1;"

  local res, err = connector:query(sql)
  if not res then
    ngx.log(ngx.ERR, "xxx err = ", err)
    return nil, err
  end

  --return tonumber(res[1].nextval)
  local first_revision = tonumber(res[1].revision)

  return first_revision
end

local function get_current_version()
  if current_version then
    return current_version
  end

  local connector = kong.db.connector

  local sql = "SELECT last_value FROM cache_revision;"

  local res, err = connector:query(sql)
  if not res then
    ngx.log(ngx.ERR, "xxx err = ", err)
    return nil, err
  end

  ngx.log(ngx.ERR, "xxx revison = ", require("inspect")(res))
  --return tonumber(res[1].nextval)
  current_version = tonumber(res[1].last_value)

  return current_version
end

function _M.export_inc_config(dp_revision)
  local dp_revision = tonumber(dp_revision)

  local current_revision = get_current_version()
  ngx.log(ngx.ERR, "xxx cp incremental ", dp_revision, "=>", current_revision)

  if dp_revision == current_revision then
    ngx.log(ngx.ERR, "xxx need not sync to dp")
    return {}
  end

  -- revision is not correct, or too old, do full sync
  if (current_revision < dp_revision ) or
     (current_revision - dp_revision > 100)
  then
    ngx.log(ngx.ERR, "xxx not correct, or too old, try full sync to dp")
    return _M.export_config()
  end

  local first_revision = get_first_changed_revision() or 1
  ngx.log(ngx.ERR, "dp_revision=", dp_revision, " first_revision=", first_revision)

  -- dp missed some changes
  if dp_revision < (first_revision - 1) then
    ngx.log(ngx.ERR, "xxx dp missed some changes, try full sync to dp")
    return _M.export_config()
  end

  assert(dp_revision >= first_revision - 1)

  local db = kong.db

  local ok, err = begin_transaction(db)
  if not ok then
    return nil, err
  end

  local export_stmt = "select revision, key, value,event " ..
                      "from cache_changes " ..
                      "where revision > " .. dp_revision
  ngx.log(ngx.ERR, "xxx _M.export_inc_config = ", export_stmt)

  local res, err = db.connector:query(export_stmt)
  if not res then
    ngx.log(ngx.ERR, "xxx err = ", err)
    end_transaction(db)
    return nil, err
  end

  end_transaction(db)

  return res
end

-- 1 => enable, 0 => disable
-- flag `SYNC_TEST` in clustering/control_plane.lua
_M.enable = 1

return _M
