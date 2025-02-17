local _M = {}
local _MT = { __index = _M, }


local hooks = require("kong.hooks")
local kong_table = require("kong.tools.table")
local EMPTY = kong_table.EMPTY


local ipairs = ipairs
local ngx_log = ngx.log
local ngx_ERR = ngx.ERR
local ngx_WARN = ngx.WARN
local ngx_DEBUG = ngx.DEBUG


local DEFAULT_PAGE_SIZE = 512


function _M.new(strategy)
  local self = {
    strategy = strategy,
  }

  return setmetatable(self, _MT)
end


local function get_all_nodes_with_sync_cap()
  local res, err = kong.db.clustering_data_planes:page(DEFAULT_PAGE_SIZE)
  if err then
    return nil, "unable to query DB " .. err
  end

  if not res then
    return EMPTY
  end

  local ret = {}
  local ret_n = 0

  for _, row in ipairs(res) do
    for _, c in ipairs(row.rpc_capabilities) do
      if c == "kong.sync.v2" then
        ret_n = ret_n + 1
        ret[ret_n] = row.id
        break
      end
    end
  end

  return ret
end


function _M:notify_all_nodes()
  local latest_version, err = self.strategy:get_latest_version()
  if not latest_version then
    ngx_log(ngx_ERR, "can not get the latest version: ", err)
    return
  end

  ngx_log(ngx_DEBUG, "[kong.sync.v2] notifying all nodes of new version: ", latest_version)

  local msg = { default = { new_version = latest_version, }, }

  for _, node in ipairs(get_all_nodes_with_sync_cap()) do
    local res, err = kong.rpc:call(node, "kong.sync.v2.notify_new_version", msg)
    if not res then
      if not err:find("requested capability does not exist", nil, true) and
         not err:find("node is not connected", nil, true)
      then
        ngx_log(ngx_ERR, "unable to notify ", node, " new version: ", err)
      end
    end
  end
end


function _M:entity_delta_writer(entity, name, options, ws_id, is_delete)
  local dao = kong.db[name]

  if not is_delete and dao and entity and entity.ttl then
    -- Replace relative TTL value to absolute TTL value
    local export_options = kong_table.cycle_aware_deep_copy(options, true)
    export_options["export"] = true
    local exported_entity = dao:select(entity, export_options)

    if exported_entity and exported_entity.ttl then
      ngx_log(ngx_DEBUG, "[kong.sync.v2] Update TTL from relative value to absolute value ", exported_entity.ttl, ".")
      entity.ttl = exported_entity.ttl

    else
      ngx_log(ngx_WARN, "[kong.sync.v2] Cannot update TTL of entity (", name, ") to absolute value.")
    end
  end

  local res, err = self.strategy:insert_delta()
  if not res then
    self.strategy:cancel_txn()
    return nil, err
  end

  res, err = self.strategy:commit_txn()
  if not res then
    self.strategy:cancel_txn()
    return nil, err
  end

  self:notify_all_nodes()

  return entity -- for other hooks
end


-- only control plane has these delta operations
function _M:register_dao_hooks()
  local function is_db_export(name)
    local db_export = kong.db[name].schema.db_export

    kong.log.trace("[kong.sync.v2] name: ", name, " db_export: ", db_export)

    return db_export == nil or db_export == true
  end

  -- common hook functions (pre/fail/post)

  local function pre_hook_func(entity, name, options)
    if not is_db_export(name) then
      return true
    end

    return self.strategy:begin_txn()
  end

  local function fail_hook_func(err, entity, name)
    if not is_db_export(name) then
      return
    end

    ngx_log(ngx_DEBUG, "[kong.sync.v2] failed. Canceling ", name)

    local res, err = self.strategy:cancel_txn()
    if not res then
      ngx_log(ngx_ERR, "unable to cancel cancel_txn: ", tostring(err))
    end
  end

  local function post_hook_writer_func(entity, name, options, ws_id)
    if not is_db_export(name) then
      return entity
    end

    ngx_log(ngx_DEBUG, "[kong.sync.v2] new delta due to writing ", name)

    return self:entity_delta_writer(entity, name, options, ws_id)
  end

  local function post_hook_delete_func(entity, name, options, ws_id, cascade_entries)
    if not is_db_export(name) then
      return entity
    end

    ngx_log(ngx_DEBUG, "[kong.sync.v2] new delta due to deleting ", name)

    return self:entity_delta_writer(entity, name, options, ws_id)
  end

  local dao_hooks = {
    -- dao:insert
    ["dao:insert:pre"]  = pre_hook_func,
    ["dao:insert:fail"] = fail_hook_func,
    ["dao:insert:post"] = post_hook_writer_func,

    -- dao:delete
    ["dao:delete:pre"]  = pre_hook_func,
    ["dao:delete:fail"] = fail_hook_func,
    ["dao:delete:post"] = post_hook_delete_func,

    -- dao:update
    ["dao:update:pre"]  = pre_hook_func,
    ["dao:update:fail"] = fail_hook_func,
    ["dao:update:post"] = post_hook_writer_func,

    -- dao:upsert
    ["dao:upsert:pre"]  = pre_hook_func,
    ["dao:upsert:fail"] = fail_hook_func,
    ["dao:upsert:post"] = post_hook_writer_func,

    -- dao:upsert_by
    ["dao:upsert_by:pre"]  = pre_hook_func,
    ["dao:upsert_by:fail"] = fail_hook_func,
    ["dao:upsert_by:post"] = post_hook_writer_func,

    -- dao:delete_by
    ["dao:delete_by:pre"]  = pre_hook_func,
    ["dao:delete_by:fail"] = fail_hook_func,
    ["dao:delete_by:post"] = post_hook_delete_func,

    -- dao:update_by
    ["dao:update_by:pre"]  = pre_hook_func,
    ["dao:update_by:fail"] = fail_hook_func,
    ["dao:update_by:post"] = post_hook_writer_func,
  }

  for ev, func in pairs(dao_hooks) do
    hooks.register_hook(ev, func)
  end
end


return _M
