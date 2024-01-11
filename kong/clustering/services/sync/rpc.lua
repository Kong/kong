local _M = {}
local _MT = { __index = _M, }


local semaphore = require("ngx.semaphore")
local lmdb = require("resty.lmdb")
local declarative = require("kong.db.declarative")


function _M.new(strategy)
  local self = {
    strategy = strategy,
    sema = semaphore.new(),
  }

  return setmetatable(self, _MT)
end


function _M:init(manager, is_cp)
  if is_cp then
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
    end)

  else
    -- DP
    manager.callbacks:register("kong.sync.v2.notify_new_version", function(node_id, version)
      self.sema:post()
      return true
    end)
  end
end


function _M:init_worker_dp()
  ngx.timer.at(0, function(premature)
    while true do
      if premature then
        return
      end

      local res, err = self.sema:wait(5)
      --if not res then
      --  if err ~= "timeout" then
      --    ngx.log(ngx.ERR, "sync semaphore error: ", err)
      --    return
      --  end
      --end

      local delta, err = kong.rpc:call("kong.sync.v2.get_delta",
                           tonumber(declarative.get_current_hash()) or 0)
      if not delta then
        ngx.log(ngx.ERR, "sync get_delta error: ", err)
      end

      local version = 0

      for _, d in ipairs(delta) do
        if d.row ~= ngx.null then
          assert(kong.db[d.type]:insert(d.row))

        else
          assert(kong.db[d.type]:remove({
            id = d.id,
          }))
        end

        if d.version ~= version then
          version = d.version
          assert(lmdb.set(DECLARATIVE_HASH_KEY, version))
        end
      end
    end
  end)
end


return _M
