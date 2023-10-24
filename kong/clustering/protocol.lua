local txn = require("kong.resty.lmdb.reset-transaction")
local utils = require("kong.tools.utils")
local cjson = require("cjson.safe")
local isempty = require("table.isempty")
local constants = require("kong.constants")
local marshaller = require("kong.db.declarative.marshaller")


local lmdb_get = require("resty.lmdb").get


local yield = utils.yield
local inflate = utils.inflate_gzip
local deflate = utils.deflate_gzip
local cjson_decode = cjson.decode
local cjson_encode = cjson.encode
local marshall = marshaller.marshall
local unmarshall = marshaller.unmarshall


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
local PREVIOUS_HASHES = {}


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
  local hash = hashes._config

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
  local hash = entity._hash
  entity._hash = nil  
  local ok, errors = schema:validate_fields(entity)
  if not ok then
    local err_t = kong.db.errors:schema_violation(errors)
    error(tostring(err_t))
  end
  if hash then
    entity._hash = hash
  end
  if ws_id then
    entity.ws_id = ws_id
  end
end


local function has_same_entities_hash(name)
  return META.hashes[name] and PREVIOUS_HASHES[name]
     and META.hashes[name] ==  PREVIOUS_HASHES[name]
      or false
end


local function process_entity_deletions(name, new_keys)
  local daos = kong.db.daos
  local dao = daos[name]
  local schema = dao.schema
  local global_key = schema.workspaceable and "*" or ""
  local global_list_key = name .. "|" .. global_key ..  "|@list"
  local prev_keys = lmdb_get(global_list_key)
  if prev_keys then
    prev_keys = unmarshall(prev_keys)
    if prev_keys and not isempty(prev_keys) then
      local uniques = get_uniques(name)
      if new_keys then
        for _, pk_key in ipairs(new_keys) do
          new_keys[pk_key] = true
        end
      end

      local lists_to_delete = new_keys and {} or { [global_list_key] = true }

      for _, pk_key in ipairs(prev_keys) do
        if not (new_keys and new_keys[pk_key]) then
          local prev_entity = lmdb_get(pk_key)
          if prev_entity then
            LMDB_TXN:del(pk_key)
            prev_entity = unmarshall(prev_entity)
            if prev_entity then
              local id = pk_string(schema, prev_entity)
              LMDB_TXN:del(dao:cache_key(id, nil, nil, nil, nil, "*"))
              if schema.cache_key then
                local cache_key = dao:cache_key(prev_entity)
                if cache_key ~= pk_key then
                  LMDB_TXN:del(cache_key)
                end
              end

              local ws_id
              if schema.workspaceable then
                if not prev_entity.ws_id or prev_entity.ws_id == null then
                  prev_entity.ws_id = META.default_workspace
                end
                ws_id = prev_entity.ws_id
              end
              local ws = ws_id or ""


              if #uniques > 0 then
                for _, unique in ipairs(uniques) do
                  local unique_key = prev_entity[unique]
                  if unique_key and unique_key ~= null then
                    if type(unique_key) == "table" then
                      -- this assumes that foreign keys are not composite
                      _, unique_key = next(unique_key)
                    end
                    LMDB_TXN:del(name .. "|" .. (schema.fields[unique].unique_across_ws and "" or ws)
                                      .. "|" .. unique .. ":" .. unique_key)
                  end
                end
              end

              if ws_id then
                lists_to_delete[name .. "|" .. ws_id ..  "|@list"] = true
              end

              for fname, ref in pairs(get_foreigns(name)) do
                local entity_fname = prev_entity[fname]
                if entity_fname and entity_fname ~= null then
                  local fid = pk_string(daos[ref].schema, entity_fname)
                  lists_to_delete[name .. "|*|" .. ref .. "|" .. fid .. "|@list"] = true
                  lists_to_delete[name .. "|" .. ws .. "|" .. ref .. "|" .. fid .. "|@list"] = true
                end
              end

              local entity_tags = prev_entity.tags
              if entity_tags and entity_tags ~= null then
                for _, tag in ipairs(entity_tags) do
                  lists_to_delete["taggings:" .. tag .. "|" .. name .. "|" .. ws .. "|@list"] = true
                  lists_to_delete["tags:" .. tag .. "|@list"] = true
                end
              end
            end
          end
        end
      end

      for key in pairs(lists_to_delete) do
        LMDB_TXN:del(key)
      end
    end
  end
end


local function process_deletions()
  for _, name in ipairs(get_topologically_sorted_schema_names()) do
    if META.hashes[name] == DECLARATIVE_EMPTY_CONFIG_HASH then
      process_entity_deletions(name)
    end
  end
end


local function process_entity_lists()
  if has_same_entities_hash(ENTITY_NAME) then
    return
  end

  process_entity_deletions(ENTITY_NAME, KEYS_BY_WS[kong.db.daos[ENTITY_NAME].schema.workspaceable and "*" or ""])

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

  local same_entities_hash = has_same_entities_hash(ENTITY_NAME)

  local daos = kong.db.daos
  local dao = assert(daos[ENTITY_NAME], "unknown entity: " .. ENTITY_NAME)
  local schema = dao.schema
  local entities = assert(cjson_decode(assert(inflate(msg.data))))

  yield(false, "timer")

  local global_key = schema.workspaceable and "*" or ""
  KEYS_BY_WS[global_key] = KEYS_BY_WS[global_key] or {}

  for _, entity in ipairs(entities) do
    yield(true, "timer")

    local id = pk_string(schema, entity)
    local ws_id
    if schema.workspaceable then
      if not entity.ws_id or entity.ws_id == null then
        entity.ws_id = META.default_workspace
      end
      ws_id = entity.ws_id
    end
    local ws = ws_id or ""
    local pk_key = dao:cache_key(id, nil, nil, nil, nil, ws_id)

    if not same_entities_hash then
      local prev_entity = lmdb_get(pk_key)
      local same_entity_hash
      if prev_entity then
        prev_entity = unmarshall(prev_entity)
        same_entity_hash = prev_entity and entity._hash == prev_entity._hash
      end
      if not same_entity_hash then
        validate_entity(schema, entity)
        local entity_marshalled = assert(marshall(entity))
        LMDB_TXN:set(pk_key, entity_marshalled)
        LMDB_TXN:set(dao:cache_key(id, nil, nil, nil, nil, "*"), entity_marshalled)
        if schema.cache_key then
          local cache_key = dao:cache_key(entity)
          if cache_key ~= pk_key then
            LMDB_TXN:set(cache_key, entity_marshalled)
          end
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
      end

      insert(KEYS_BY_WS[global_key], pk_key)
      if ws_id then
        KEYS_BY_WS[ws_id] = KEYS_BY_WS[ws_id] or {}
        insert(KEYS_BY_WS[ws_id], pk_key)
      end

      for fname, ref in pairs(get_foreigns(ENTITY_NAME)) do
        local entity_fname = entity[fname]
        if entity_fname and entity_fname ~= null then
          local fid = pk_string(daos[ref].schema, entity_fname)

          -- insert paged search entry for global query
          PAGE_FOR[ref] = PAGE_FOR[ref] or {}
          PAGE_FOR[ref]["*"] = PAGE_FOR[ref]["*"] or {}
          PAGE_FOR[ref]["*"][fid] = PAGE_FOR[ref]["*"][fid] or {}
          insert(PAGE_FOR[ref]["*"][fid], pk_key)

          -- insert paged search entry for workspaced query
          PAGE_FOR[ref][ws] = PAGE_FOR[ref][ws] or {}
          PAGE_FOR[ref][ws][fid] = PAGE_FOR[ref][ws][fid] or {}
          insert(PAGE_FOR[ref][ws][fid], pk_key)
        end
      end
    end

    local entity_tags = entity.tags
    if entity_tags and entity_tags ~= null then
      for _, tag in ipairs(entity_tags) do
        if not same_entities_hash then
          TAGGINGS[tag] = TAGGINGS[tag] or {}
          TAGGINGS[tag][ws] = TAGGINGS[tag][ws] or {}
          TAGGINGS[tag][ws][pk_key] = true
        end
        insert(TAGS, tag .. "|" .. ENTITY_NAME .. "|" .. id)
        TAGS_BY_NAME[tag] = TAGS_BY_NAME[tag] or {}
        insert(TAGS_BY_NAME[tag], tag .. "|" .. ENTITY_NAME .. "|" .. id)
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

  process_deletions()

  for tag, tags in pairs(TAGS_BY_NAME) do
    LMDB_TXN:set("tags:" .. tag .. "|@list", assert(marshall(tags)))
  end
  LMDB_TXN:set("tags||@list", assert(marshall(TAGS)))
  LMDB_TXN:set(DECLARATIVE_HASH_KEY, HASH)

  yield(false, "timer")

  assert(LMDB_TXN:commit())

  PREVIOUS_HASHES = META.hashes

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
