local txn = require("kong.resty.lmdb.reset-transaction")
local utils = require("kong.tools.utils")
local cjson = require("cjson.safe")
local isempty = require("table.isempty")
local constants = require("kong.constants")


local yield = utils.yield
local inflate = utils.inflate_gzip
local deflate = utils.deflate_gzip
local cjson_decode = cjson.decode
local cjson_encode = cjson.encode


local marshall = require("kong.db.declarative.marshaller").marshall
local pk_string = require("kong.db.schema.others.declarative_config").pk_string
local get_topologically_sorted_schema_names = require("kong.db.declarative.export").get_topologically_sorted_schema_names
local declarative_reconfigure_notify = require("kong.runloop.events").declarative_reconfigure_notify


local DECLARATIVE_HASH_KEY = constants.DECLARATIVE_HASH_KEY
local DECLARATIVE_EMPTY_CONFIG_HASH = constants.DECLARATIVE_EMPTY_CONFIG_HASH


local kong = kong
local md5 = ngx.md5
local null = ngx.null
local type = type
local next = next
local sort = table.sort
local error = error
local pairs = pairs
local ipairs = ipairs
local assert = assert
local insert = table.insert
local tostring = tostring


local LMDB_TXN
local HASH
local META
local ENTITY_NAME
local KEYS_BY_WS = {}
local PAGE_FOR = {}
local TAGS = {}
local TAGS_BY_NAME = {}
local TAGGINGS = {}


local UNIQUES = {}
local FOREIGNS = {}


local MAX_ENTITIES = 1000


local function send_binary(wb, tbl)
  local _, err = wb:send_binary(cjson_encode(tbl))
  if err then
    return error("unable to send updated configuration to data plane: " .. err)
  end
end


local function send_configuration_payload(wb, payload)
  local timetamp = payload.timestamp
  local config = payload.config
  local hashes = payload.hashes
  local hash = hashes.config

  send_binary(wb, {
    type = "reconfigure:start",
    hash = hash,
    meta = {
      timestamp = timetamp,
      format_version = config._format_version,
      default_workspace = kong.default_workspace,
      hashes = hashes,
    }
  })

  yield(false, "timer")

  local batch = kong.table.new(0, MAX_ENTITIES)
  for _, name in ipairs(get_topologically_sorted_schema_names()) do
    local entities = config[name]
    if entities and not isempty(entities) then
      local count = #entities
      if count <= MAX_ENTITIES then
        send_binary(wb, {
          type = "entities",
          hash = hash,
          name = name,
          data = assert(deflate(assert(cjson_encode(entities)))),
        })

        yield(true, "timer")

      else
        local i = 0
        for j, entity in ipairs(entities) do
          i = i + 1
          batch[i] = entity
          if i == MAX_ENTITIES or j == count then
            send_binary(wb, {
              type = "entities",
              hash = hash,
              name = name,
              data = assert(deflate(assert(cjson_encode(batch)))),
            })

            yield(true, "timer")
            kong.table.clear(batch)
            i = 0
          end
        end
      end
    end
  end

  send_binary(wb, {
    type = "reconfigure:end",
    hash = hash,
  })
end


local function reset_values()
  LMDB_TXN = nil
  HASH = nil
  META = nil
  ENTITY_NAME = nil

  kong.table.clear(KEYS_BY_WS)
  kong.table.clear(PAGE_FOR)
  kong.table.clear(TAGS)
  kong.table.clear(TAGS_BY_NAME)
  kong.table.clear(TAGGINGS)
end


local function get_reconfigure_data()
  local router_hash   = DECLARATIVE_EMPTY_CONFIG_HASH
  local plugins_hash  = DECLARATIVE_EMPTY_CONFIG_HASH
  local balancer_hash = DECLARATIVE_EMPTY_CONFIG_HASH
  local hashes        = META.hashes
  if hashes then
    local routes_hash   = hashes.routes   or DECLARATIVE_EMPTY_CONFIG_HASH
    local services_hash = hashes.services or DECLARATIVE_EMPTY_CONFIG_HASH
    if routes_hash ~= DECLARATIVE_EMPTY_CONFIG_HASH then
      router_hash = md5(services_hash .. routes_hash)
    end

    if hashes.plugins then
      plugins_hash = hashes.plugins
    end

    local upstreams_hash = hashes.upstreams or DECLARATIVE_EMPTY_CONFIG_HASH
    local targets_hash   = hashes.targets   or DECLARATIVE_EMPTY_CONFIG_HASH
    if upstreams_hash ~= DECLARATIVE_EMPTY_CONFIG_HASH
    or targets_hash   ~= DECLARATIVE_EMPTY_CONFIG_HASH
    then
      balancer_hash = md5(upstreams_hash .. targets_hash)
    end
  end

  return {
    META.default_workspace,
    router_hash,
    plugins_hash,
    balancer_hash,
  }
end


local function get_uniques(name)
  if UNIQUES[name] then
    return UNIQUES[name]
  end

  local daos = kong.db.daos
  local dao = assert(daos[name], "unknown entity: " .. name)
  local schema = dao.schema

  local uniques = {}
  for fname, fdata in schema:each_field() do
    if fdata.unique then
      if fdata.type == "foreign" then
        if #daos[fdata.reference].schema.primary_key == 1 then
          insert(uniques, fname)
        end

      else
        insert(uniques, fname)
      end
    end
  end
  UNIQUES[name] = uniques
  return uniques
end


local function get_foreigns(name)
  if FOREIGNS[name] then
    return FOREIGNS[name]
  end

  local daos = kong.db.daos
  local dao = assert(daos[name], "unknown entity: " .. name)
  local schema = dao.schema

  local foreigns = {}
  for fname, fdata in schema:each_field() do
    if fdata.type == "foreign" then
      foreigns[fname] = fdata.reference
    end
  end
  FOREIGNS[name] = foreigns
  return foreigns
end


local function validate_entity(schema, entity)
  local ws_id = schema.workspaceable and entity.ws_id or nil
  if ws_id then
    entity.ws_id = nil
  end
  local ok, errors = schema:validate_fields(entity)
  if not ok then
    local err_t = kong.db.errors:schema_violation(errors)
    error(tostring(err_t))
  end
  if ws_id then
    entity.ws_id = ws_id
  end
end


local function process_entity_lists()
  for ws_id, keys in pairs(KEYS_BY_WS) do
    local entity_prefix = ENTITY_NAME .. "|" .. ws_id
    LMDB_TXN:set(entity_prefix .. "|@list", assert(marshall(keys)))
    for ref, workspaces in pairs(PAGE_FOR) do
      if workspaces[ws_id] then
        for fid, entries in pairs(workspaces[ws_id]) do
          LMDB_TXN:set(entity_prefix .. "|" .. ref .. "|" .. fid .. "|@list", assert(marshall(entries)))
        end
      end
    end
  end

  for tag_name, workspaces_dict in pairs(TAGGINGS) do
    for ws_id, keys_dict in pairs(workspaces_dict) do
      local arr, len = {}, 0
      for id in pairs(keys_dict) do
        len = len + 1
        arr[len] = id
      end
      sort(arr)
      LMDB_TXN:set("taggings:" .. tag_name .. "|" .. ENTITY_NAME .. "|" .. ws_id .. "|@list", assert(marshall(arr)))
    end
  end
end


local function reconfigure_start(msg)
  reset_values()

  LMDB_TXN = txn.begin()

  HASH = msg.hash
  META = msg.meta

  return true
end


local function process_entities(msg)
  assert(HASH == msg.hash, "reconfigure hash mismatch")

  if ENTITY_NAME ~= msg.name then
    if ENTITY_NAME then
      process_entity_lists()
    end

    ENTITY_NAME = msg.name

    kong.table.clear(KEYS_BY_WS)
    kong.table.clear(PAGE_FOR)
    kong.table.clear(TAGGINGS)

    yield(false, "timer")
  end

  local daos = kong.db.daos
  local dao = assert(daos[ENTITY_NAME], "unknown entity: " .. ENTITY_NAME)
  local schema = dao.schema
  local entities = assert(cjson_decode(assert(inflate(msg.data))))

  yield(false, "timer")

  local global_key = schema.workspaceable and "*" or ""
  KEYS_BY_WS[global_key] = KEYS_BY_WS[global_key] or {}

  for _, entity in ipairs(entities) do
    yield(true, "timer")

    validate_entity(schema, entity)

    local id = pk_string(schema, entity)
    local ws_id
    if schema.workspaceable then
      if not entity.ws_id or entity.ws_id == null then
        entity.ws_id = META.default_workspace
      end
      ws_id = entity.ws_id
    end
    local ws = ws_id or ""
    local cache_key = dao:cache_key(id, nil, nil, nil, nil, ws_id)
    local entity_marshalled = assert(marshall(entity))
    LMDB_TXN:set(cache_key, entity_marshalled)
    LMDB_TXN:set(dao:cache_key(id, nil, nil, nil, nil, "*"), entity_marshalled)
    if schema.cache_key then
      LMDB_TXN:set(dao:cache_key(entity), entity_marshalled)
    end

    insert(KEYS_BY_WS[global_key], cache_key)
    if ws_id then
      KEYS_BY_WS[ws_id] = KEYS_BY_WS[ws_id] or {}
      insert(KEYS_BY_WS[ws_id], cache_key)
    end

    for _, unique in ipairs(get_uniques(ENTITY_NAME)) do
      local unique_key = entity[unique]
      if unique_key and unique_key ~= null then
        if type(unique_key) == "table" then
          -- this assumes that foreign keys are not composite
          _, unique_key = next(unique_key)
        end
        LMDB_TXN:set(ENTITY_NAME .. "|" .. (schema.fields[unique].unique_across_ws and "" or ws)
                                 .. "|" .. unique .. ":" .. unique_key, entity_marshalled)
      end
    end

    for fname, ref in pairs(get_foreigns(ENTITY_NAME)) do
      local entity_fname = entity[fname]
      if entity_fname and entity_fname ~= null then
        local fid = pk_string(daos[ref].schema, entity_fname)

        -- insert paged search entry for global query
        PAGE_FOR[ref] = PAGE_FOR[ref] or {}
        PAGE_FOR[ref]["*"] = PAGE_FOR[ref]["*"] or {}
        PAGE_FOR[ref]["*"][fid] = PAGE_FOR[ref]["*"][fid] or {}
        insert(PAGE_FOR[ref]["*"][fid], cache_key)

        -- insert paged search entry for workspaced query
        PAGE_FOR[ref][ws] = PAGE_FOR[ref][ws] or {}
        PAGE_FOR[ref][ws][fid] = PAGE_FOR[ref][ws][fid] or {}
        insert(PAGE_FOR[ref][ws][fid], cache_key)
      end
    end

    local entity_tags = entity.tags
    if entity_tags and entity.tags ~= null then
      for _, tag in ipairs(entity_tags) do
        insert(TAGS, tag .. "|" .. ENTITY_NAME .. "|" .. id)
        TAGS_BY_NAME[tag] = TAGS_BY_NAME[tag] or {}
        insert(TAGS_BY_NAME[tag], tag .. "|" .. ENTITY_NAME .. "|" .. id)
        TAGGINGS[tag] = TAGGINGS[tag] or {}
        TAGGINGS[tag][ws] = TAGGINGS[tag][ws] or {}
        TAGGINGS[tag][ws][cache_key] = true
      end
    end
  end

  return true
end


local function reconfigure_end(msg)
  assert(HASH == msg.hash, "reconfigure hash mismatch")
  if ENTITY_NAME then
    process_entity_lists()
  end
  for tag, tags in pairs(TAGS_BY_NAME) do
    LMDB_TXN:set("tags:" .. tag .. "|@list", assert(marshall(tags)))
  end
  LMDB_TXN:set("tags||@list", assert(marshall(TAGS)))
  LMDB_TXN:set(DECLARATIVE_HASH_KEY, HASH)

  yield(false, "timer")

  assert(LMDB_TXN:commit())
  assert(declarative_reconfigure_notify(get_reconfigure_data()))
  reset_values()

  return true
end


return {
  send_configuration_payload = send_configuration_payload,
  reconfigure_start = reconfigure_start,
  process_entities = process_entities,
  reconfigure_end = reconfigure_end,
}
