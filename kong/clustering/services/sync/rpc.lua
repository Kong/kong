local _M = {}
local _M = { __index = _M, }


local semaphore = require("ngx.semaphore")
local lmdb = require("resty.lmdb")


function _M.new(strategy)
  local self = {
    strategy = strategy,
    sema = semaphore.new(),
  }

  return setmetatable(self, _MT)
end


function _M:init_server(manager)
  manager.callbacks:register("kong.sync.v2.get_delta", function(node_id, version)
    ngx.log(ngx.ERR, "node_id: ", node_id, " get_delta: ", version)

    local ok, err = kong.db.clustering_data_planes:upsert({ id = node_id }, {
      last_seen = ngx.time(),
      hostname = node_id,
      ip = "127.0.0.1",
      version = "3.6.0.0",
      sync_status = "normal",
      version = version,
    })
    if not ok then
      ngx.log(ngx.ERR, "unable to update clustering data plane status: ", err)
    end

    return self.strategy:get_delta(version)
end


function _M:init_worker_client()
  ngx.timer.at(0, function(premature)
    while true do
      if premature then
        return
      end

      local res, err = self.sema:wait(5)
      if not res then
        if err ~= "timeout" then
          ngx.log(ngx.ERR, "sync semaphore error: ", err)
          return
        end
      end

      local delta, err = kong.rpc:call("kong.sync.v2.get_delta", lmdb.get("DECLARATIVE_VERSION") or 0)
      if not delta then
        ngx.log(ngx.ERR, "sync get_delta error: ", err)
      end

      for _, d in ipairs(delta) do
        if d.row == ngx.null then
          kong.db[d.type].delete(d.id, {
          })
        end
      end
    end
  end)
end


function _M:init_client(manager)
  manager.callbacks:register("kong.sync.v2.notify_new_version", function(node_id, version)
    local res, err = manager:call("kong.sync.v2.get_delta")
    if not res then
    end
  end)
end


return _M
