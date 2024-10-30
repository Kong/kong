local _M = {}
local _MT = { __index = _M, }


local hooks = require("kong.hooks")
local EMPTY = require("kong.tools.table").EMPTY


local ipairs = ipairs
local ngx_null = ngx.null
local ngx_log = ngx.log
local ngx_ERR = ngx.ERR
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

  local msg = { default = { new_version = latest_version, }, }

  for _, node in ipairs(get_all_nodes_with_sync_cap()) do
    local res, err = kong.rpc:call(node, "kong.sync.v2.notify_new_version", msg)
    if not res then
      if not err:find("requested capability does not exist", nil, true) then
        ngx_log(ngx_ERR, "unable to notify new version: ", err)
      end

    else
      ngx_log(ngx_DEBUG, "notified ", node, " ", latest_version)
    end
  end
end


function _M:entity_delta_writer(entity, name, options, ws_id, is_delete)
  -- composite key, like { id = ... }
  local schema = kong.db[name].schema
  local pk = schema:extract_pk_values(entity)

  assert(schema:validate_primary_key(pk))

  local deltas = {
    {
      type = name,
      pk = pk,
      ws_id = ws_id,
      entity = is_delete and ngx_null or entity,
    },
  }

  local res, err = self.strategy:insert_delta(deltas)
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

    local res, err = self.strategy:cancel_txn()
    if not res then
      ngx_log(ngx_ERR, "unable to cancel cancel_txn: ", tostring(err))
    end
  end

  local function post_hook_writer_func(entity, name, options, ws_id)
    if not is_db_export(name) then
      return entity
    end

    return self:entity_delta_writer(entity, name, options, ws_id)
  end

  local function post_hook_delete_func(entity, name, options, ws_id, cascade_entries)
    if not is_db_export(name) then
      return entity
    end

    -- set lmdb value to ngx_null then return entity
    return self:entity_delta_writer(entity, name, options, ws_id, true)
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
  }

  for ev, func in pairs(dao_hooks) do
    hooks.register_hook(ev, func)
  end
end


return _M
