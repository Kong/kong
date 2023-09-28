local txn = require("kong.resty.lmdb.reset-transaction")
local declarative = require("kong.db.declarative")
local tablepool = require("tablepool")
local isarray = require("table.isarray")
local nkeys = require("table.nkeys")
local buffer = require("string.buffer")
local isempty = require("table.isempty")
local constants = require("kong.constants")


local marshall = require("kong.db.declarative.marshaller").marshall
local pk_string = require("kong.db.schema.others.declarative_config").pk_string
local get_topologically_sorted_schema_names = require("kong.db.declarative.export").get_topologically_sorted_schema_names
local declarative_reconfigure_notify = require("kong.runloop.events").declarative_reconfigure_notify


local next = next
local tostring = tostring
local ipairs = ipairs
local assert = assert
local type = type
local error = error
local pairs = pairs
local sort = table.sort
local insert = table.insert
local yield = require("kong.tools.utils").yield
local fetch_table = tablepool.fetch
local release_table = tablepool.release


local ngx_log = ngx.log
local ngx_null = ngx.null
local ngx_md5 = ngx.md5
local ngx_md5_bin = ngx.md5_bin


local ngx_DEBUG = ngx.DEBUG


local DECLARATIVE_HASH_KEY = constants.DECLARATIVE_HASH_KEY
local DECLARATIVE_EMPTY_CONFIG_HASH = constants.DECLARATIVE_EMPTY_CONFIG_HASH


local _log_prefix = "[clustering] "


local _M = {}


local UNIQUES = {}
local FOREIGNS = {}


local function to_sorted_string(value, o)
  yield(true)

  if #o > 1000000 then
    o:set(ngx_md5_bin(o:tostring()))
  end

  if value == ngx_null then
    o:put("/null/")

  else
    local t = type(value)
    if t == "string" or t == "number" then
      o:put(value)

    elseif t == "boolean" then
      o:put(tostring(value))

    elseif t == "table" then
      if isempty(value) then
        o:put("{}")

      elseif isarray(value) then
        local count = #value
        if count == 1 then
          to_sorted_string(value[1], o)
        elseif count == 2 then
          to_sorted_string(value[1], o)
          o:put(";")
          to_sorted_string(value[2], o)

        elseif count == 3 then
          to_sorted_string(value[1], o)
          o:put(";")
          to_sorted_string(value[2], o)
          o:put(";")
          to_sorted_string(value[3], o)

        elseif count == 4 then
          to_sorted_string(value[1], o)
          o:put(";")
          to_sorted_string(value[2], o)
          o:put(";")
          to_sorted_string(value[3], o)
          o:put(";")
          to_sorted_string(value[4], o)

        elseif count == 5 then
          to_sorted_string(value[1], o)
          o:put(";")
          to_sorted_string(value[2], o)
          o:put(";")
          to_sorted_string(value[3], o)
          o:put(";")
          to_sorted_string(value[4], o)
          o:put(";")
          to_sorted_string(value[5], o)

        else
          for i = 1, count do
            to_sorted_string(value[i], o)
            o:put(";")
          end
        end

      else
        local count = nkeys(value)
        local keys = fetch_table("hash-calc", count, 0)
        local i = 0
        for k in pairs(value) do
          i = i + 1
          keys[i] = k
        end

        sort(keys)

        for i = 1, count do
          o:put(keys[i])
          o:put(":")
          to_sorted_string(value[keys[i]], o)
          o:put(";")
        end

        release_table("hash-calc", keys)
      end

    else
      error("invalid type to be sorted (JSON types are supported)")
    end
  end
end

local function calculate_hash(input, o)
  if input == nil then
    return DECLARATIVE_EMPTY_CONFIG_HASH
  end

  o:reset()
  to_sorted_string(input, o)
  return ngx_md5(o:tostring())
end


local function calculate_config_hash(config_table)
  local o = buffer.new()
  if type(config_table) ~= "table" then
    local config_hash = calculate_hash(config_table, o)
    return config_hash, { config = config_hash, }
  end

  local routes    = config_table.routes
  local services  = config_table.services
  local plugins   = config_table.plugins
  local upstreams = config_table.upstreams
  local targets   = config_table.targets

  local routes_hash = calculate_hash(routes, o)
  local services_hash = calculate_hash(services, o)
  local plugins_hash = calculate_hash(plugins, o)
  local upstreams_hash = calculate_hash(upstreams, o)
  local targets_hash = calculate_hash(targets, o)

  config_table.routes    = nil
  config_table.services  = nil
  config_table.plugins   = nil
  config_table.upstreams = nil
  config_table.targets   = nil

  local rest_hash = calculate_hash(config_table, o)
  local config_hash = ngx_md5(routes_hash    ..
                              services_hash  ..
                              plugins_hash   ..
                              upstreams_hash ..
                              targets_hash   ..
                              rest_hash)

  config_table.routes    = routes
  config_table.services  = services
  config_table.plugins   = plugins
  config_table.upstreams = upstreams
  config_table.targets   = targets

  return config_hash, {
    config    = config_hash,
    routes    = routes_hash,
    services  = services_hash,
    plugins   = plugins_hash,
    upstreams = upstreams_hash,
    targets   = targets_hash,
  }
end


local function get_reconfigure_data(hashes, default_ws)
  local router_hash   = DECLARATIVE_EMPTY_CONFIG_HASH
  local plugins_hash  = DECLARATIVE_EMPTY_CONFIG_HASH
  local balancer_hash = DECLARATIVE_EMPTY_CONFIG_HASH
  if hashes then
    local routes_hash   = hashes.routes   or DECLARATIVE_EMPTY_CONFIG_HASH
    local services_hash = hashes.services or DECLARATIVE_EMPTY_CONFIG_HASH
    if routes_hash ~= DECLARATIVE_EMPTY_CONFIG_HASH then
      router_hash = ngx_md5(services_hash .. routes_hash)
    end

    if hashes.plugins then
      plugins_hash = hashes.plugins
    end

    local upstreams_hash = hashes.upstreams or DECLARATIVE_EMPTY_CONFIG_HASH
    local targets_hash   = hashes.targets   or DECLARATIVE_EMPTY_CONFIG_HASH
    if upstreams_hash ~= DECLARATIVE_EMPTY_CONFIG_HASH
            or targets_hash   ~= DECLARATIVE_EMPTY_CONFIG_HASH
    then
      balancer_hash = ngx_md5(upstreams_hash .. targets_hash)
    end
  end

  return {
    default_ws,
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
  local ws_id
  if schema.workspaceable then
    ws_id = entity.ws_id
    entity.ws_id = nil
  end
  local ok, errors = schema:validate_insert(entity)
  if not ok then
    local err_t = kong.db.errors:schema_violation(errors)
    error(tostring(err_t))
  end
  if ws_id and ws_id ~= ngx_null then
    entity.ws_id = ws_id
  end
end


local function import(config_table, config_hash, default_ws)
  local daos = kong.db.daos
  local t = txn.begin()

  local tags = {}
  local tags_by_name = {}

  for _, name in ipairs(get_topologically_sorted_schema_names(false)) do
    local entities = config_table[name]
    if not entities then
      goto continue
    end

    local dao = assert(daos[name], "unknown entity: " .. name)
    local schema = dao.schema
    local global_key = schema.workspaceable and "*" or ""

    local keys_by_ws = { [global_key] = {} }
    local page_for = {}
    local taggings = {}

    for _, entity in ipairs(entities) do
      validate_entity(schema, entity)
      local id = pk_string(schema, entity)
      local ws_id
      if schema.workspaceable then
        if not entity.ws_id or entity.ws_id == ngx_null then
          entity.ws_id = default_ws
        end
        ws_id = entity.ws_id
      end
      local ws = ws_id or ""
      local cache_key = dao:cache_key(id, nil, nil, nil, nil, ws_id)
      local entity_marshalled = assert(marshall(entity))
      t:set(cache_key, entity_marshalled)
      t:set(dao:cache_key(id, nil, nil, nil, nil, "*"), entity_marshalled)
      if schema.cache_key then
        t:set(dao:cache_key(entity), entity_marshalled)
      end

      insert(keys_by_ws[global_key], cache_key)
      if ws_id then
        keys_by_ws[ws_id] = keys_by_ws[ws_id] or {}
        insert(keys_by_ws[ws_id], cache_key)
      end

      for _, unique in ipairs(get_uniques(name)) do
        local unique_key = entity[unique]
        if unique_key and unique_key ~= ngx_null then
          if type(unique_key) == "table" then
            -- this assumes that foreign keys are not composite
            _, unique_key = next(unique_key)
          end
          t:set(name .. "|" .. (schema.fields[unique].unique_across_ws and "" or ws)
                  .. "|" .. unique .. ":" .. unique_key, entity_marshalled)
        end
      end

      for fname, ref in pairs(get_foreigns(name)) do
        local entity_fname = entity[fname]
        if entity_fname and entity_fname ~= ngx_null then
          local fid = pk_string(daos[ref].schema, entity_fname)

          -- insert paged search entry for global query
          page_for[ref] = page_for[ref] or {}
          page_for[ref]["*"] = page_for[ref]["*"] or {}
          page_for[ref]["*"][fid] = page_for[ref]["*"][fid] or {}
          insert(page_for[ref]["*"][fid], cache_key)

          -- insert paged search entry for workspaced query
          page_for[ref][ws] = page_for[ref][ws] or {}
          page_for[ref][ws][fid] = page_for[ref][ws][fid] or {}
          insert(page_for[ref][ws][fid], cache_key)
        end
      end

      local entity_tags = entity.tags
      if entity_tags and entity.tags ~= ngx_null then
        for _, tag in ipairs(entity_tags) do
          insert(tags, tag .. "|" .. name .. "|" .. id)
          tags_by_name[tag] = tags_by_name[tag] or {}
          insert(tags_by_name[tag], tag .. "|" .. name .. "|" .. id)
          taggings[tag] = taggings[tag] or {}
          taggings[tag][ws] = taggings[tag][ws] or {}
          taggings[tag][ws][cache_key] = true
        end
      end
    end

    for ws_id, keys in pairs(keys_by_ws) do
      local entity_prefix = name .. "|" .. ws_id
      t:set(entity_prefix .. "|@list", assert(marshall(keys)))
      for ref, workspaces in pairs(page_for) do
        if workspaces[ws_id] then
          for fid, entries in pairs(workspaces[ws_id]) do
            t:set(entity_prefix .. "|" .. ref .. "|" .. fid .. "|@list", assert(marshall(entries)))
          end
        end
      end
    end

    for tag_name, workspaces_dict in pairs(taggings) do
      for ws_id, keys_dict in pairs(workspaces_dict) do
        local arr, len = {}, 0
        for id in pairs(keys_dict) do
          len = len + 1
          arr[len] = id
        end
        sort(arr)
        t:set("taggings:" .. tag_name .. "|" .. name .. "|" .. ws_id .. "|@list", assert(marshall(arr)))
      end
    end

    ::continue::
  end

  for tag, tags in pairs(tags_by_name) do
    t:set("tags:" .. tag .. "|@list", assert(marshall(tags)))
  end
  t:set("tags||@list", assert(marshall(tags)))
  t:set(DECLARATIVE_HASH_KEY, config_hash)

  return t:commit()
end


local function find_default_ws(config_table)
  for _, ws in ipairs(config_table.workspaces) do
    if ws.name == "default" then
      return ws.id
    end
  end
end


function _M.update(config_table, config_hash, hashes)
  assert(type(config_table) == "table")

  local current_hash = declarative.get_current_hash()
  if current_hash == config_hash then
    ngx_log(ngx_DEBUG, _log_prefix, "same config received from control plane, no need to reload")
    return true
  end

  local default_ws = assert(find_default_ws(config_table))

  local ok, err = import(config_table, config_hash, default_ws)
  if not ok then
    return nil, err
  end

  return declarative_reconfigure_notify(get_reconfigure_data(hashes, default_ws))
end


_M.calculate_config_hash = calculate_config_hash


return _M
