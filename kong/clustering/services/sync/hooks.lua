local _M = {}
local _MT = { __index = _M, }


local hooks = require("kong.hooks")
local constants = require("kong.constants")


local CLUSTERING_PING_INTERVAL = constants.CLUSTERING_PING_INTERVAL


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


function _M:register_dao_hooks(is_cp)
  -- only control plane has these delta operations
  if not is_cp then
    return
  end

  -- dao:insert

  hooks.register_hook("dao:insert:pre", function()
    return self.strategy:begin_txn()
  end)

  hooks.register_hook("dao:insert:fail", function()
    return self.strategy:cancel_txn()
  end)

  hooks.register_hook("dao:insert:post", function(row, name, options, ws_id)
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

    local latest_version = self.strategy:get_latest_version()

    for _, node in ipairs(get_all_nodes_with_sync_cap()) do
      res, err = kong.rpc:call(node, "kong.sync.v2.notify_new_version", latest_version)
      if not res then
        if not err:find("requested capability does not exist", nil, true) then
          ngx.log(ngx.ERR, "unable to notify new version: ", err)
        end

      else
        ngx.log(ngx.ERR, "notified ", node, " ", latest_version)
      end
    end

    return row, name, options, ws_id
  end)

  -- dao:delete

  hooks.register_hook("dao:delete:pre", function()
    return self.strategy:begin_txn()
  end)

  hooks.register_hook("dao:delete:fail", function(err)
    if err then
      return self.strategy:cancel_txn()
    else
      return self.strategy:commit_txn()
    end
  end)

  hooks.register_hook("dao:delete:post", function(row, name, options, ws_id, cascade_entries)
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

    local latest_version = self.strategy:get_latest_version()

    for _, node in ipairs(get_all_nodes_with_sync_cap()) do
      res, err = kong.rpc:call(node, "kong.sync.v2.notify_new_version", latest_version)
      if not res then
        if not err:find("requested capability does not exist", nil, true) then
          ngx.log(ngx.ERR, "unable to notify new version: ", err)
        end

      else
        ngx.log(ngx.ERR, "notified ", node, " ", latest_version)
      end
    end

    return row, name, options, ws_id, cascade_entries
  end)
end


return _M