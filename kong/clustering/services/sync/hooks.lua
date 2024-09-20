local _M = {}
local _MT = { __index = _M, }


local hooks = require("kong.hooks")
--local constants = require("kong.constants")


--local CLUSTERING_PING_INTERVAL = constants.CLUSTERING_PING_INTERVAL
local ngx_log = ngx.log
--local ngx_DEBUG = ngx.DEBUG
local ngx_ERR = ngx.ERR


function _M.new(strategy)
  local self = {
    strategy = strategy,
  }

  return setmetatable(self, _MT)
end


local function get_all_nodes_with_sync_cap()
  local ret = {}
  local ret_n = 0

  local res, err = kong.db.clustering_data_planes:page(512)
  if err then
    return nil, "unable to query DB " .. err
  end

  if not res then
    return {}
  end

  for _, row in ipairs(res) do
    for _, c in ipairs(row.rpc_capabilities) do
      if c == "kong.sync.v2" then
        ret_n = ret_n + 1
        ret[ret_n] = row.id
      end
    end
  end

  return ret
end


function _M:notify_all_nodes(new_version)
  local latest_version = self.strategy:get_latest_version()

  for _, node in ipairs(get_all_nodes_with_sync_cap()) do
    local res, err = kong.rpc:call(node, "kong.sync.v2.notify_new_version",
                             { default = { new_version = latest_version, }, })
    if not res then
      if not err:find("requested capability does not exist", nil, true) then
        ngx.log(ngx.ERR, "unable to notify new version: ", err)
      end

    else
      ngx.log(ngx.ERR, "notified ", node, " ", latest_version)
    end
  end
end


function _M:entity_delta_writer(row, name, options, ws_id)
  local deltas = {
    {
      ["type"] = name,
      id = row.id,
      ws_id = ws_id,
      row = row, },
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

  return row
end


function _M:register_dao_hooks(is_cp)
  -- only control plane has these delta operations
  if not is_cp then
    return
  end

  -- dao:insert

  hooks.register_hook("dao:insert:pre", function(entity, name, options)
    local db_export = kong.db[name].schema.db_export
    if db_export == nil or db_export == true then
      return self.strategy:begin_txn()
    end

    return true
  end)

  hooks.register_hook("dao:insert:fail", function(err, entity, name)
    local db_export = kong.db[name].schema.db_export
    if db_export == nil or db_export == true then
      local res, err = self.strategy:cancel_txn()
      if not res then
        ngx_log(ngx_ERR, "unable to cancel cancel_txn: ", err)
      end
    end
  end)

  hooks.register_hook("dao:insert:post", function(row, name, options, ws_id)
    local db_export = kong.db[name].schema.db_export
    if db_export == nil or db_export == true then
      return self:entity_delta_writer(row, name, options, ws_id)
    end

    return row
  end)

  -- dao:delete

  hooks.register_hook("dao:delete:pre", function(entity, name, options)
    local db_export = kong.db[name].schema.db_export
    if db_export == nil or db_export == true then
      return self.strategy:begin_txn()
    end

    return true
  end)

  hooks.register_hook("dao:delete:fail", function(err, entity, name)
    local db_export = kong.db[name].schema.db_export
    if db_export == nil or db_export == true then
      local res, err = self.strategy:cancel_txn()
      if not res then
        ngx_log(ngx_ERR, "unable to cancel cancel_txn: ", err)
      end
    end
  end)

  hooks.register_hook("dao:delete:post", function(row, name, options, ws_id, cascade_entries)
    local db_export = kong.db[name].schema.db_export
    if db_export == nil or db_export == true then
      local deltas = {
        {
          ["type"] = name,
          id = row.id,
          ws_id = ws_id,
          row = ngx.null, },
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
    end

    return row
  end)

  -- dao:update

  hooks.register_hook("dao:update:pre", function(entity, name, options)
    local db_export = kong.db[name].schema.db_export
    if db_export == nil or db_export == true then
      return self.strategy:begin_txn()
    end

    return true
  end)

  hooks.register_hook("dao:update:fail", function(err, entity, name)
    local db_export = kong.db[name].schema.db_export
    if db_export == nil or db_export == true then
      local res, err = self.strategy:cancel_txn()
      if not res then
        ngx_log(ngx_ERR, "unable to cancel cancel_txn: ", err)
      end
    end
  end)

  hooks.register_hook("dao:update:post", function(row, name, options, ws_id)
    local db_export = kong.db[name].schema.db_export
    if db_export == nil or db_export == true then
      return self:entity_delta_writer(row, name, options, ws_id)
    end

    return row
  end)

  -- dao:upsert

  hooks.register_hook("dao:upsert:pre", function(entity, name, options)
    local db_export = kong.db[name].schema.db_export
    if db_export == nil or db_export == true then
      return self.strategy:begin_txn()
    end

    return true
  end)

  hooks.register_hook("dao:upsert:fail", function(err, entity, name)
    local db_export = kong.db[name].schema.db_export
    if db_export == nil or db_export == true then
      local res, err = self.strategy:cancel_txn()
      if not res then
        ngx_log(ngx_ERR, "unable to cancel cancel_txn: ", err)
      end
    end
  end)

  hooks.register_hook("dao:upsert:post", function(row, name, options, ws_id)
    local db_export = kong.db[name].schema.db_export
    if db_export == nil or db_export == true then
      return self:entity_delta_writer(row, name, options, ws_id)
    end

    return row
  end)
end


return _M
