local _M = {}
local _MT = { __index = _M, }


local semaphore = require("ngx.semaphore")
local lmdb = require("resty.lmdb")
local declarative = require("kong.db.declarative")
local constants = require("kong.constants")
local concurrency = require("kong.concurrency")


local DECLARATIVE_HASH_KEY = constants.DECLARATIVE_HASH_KEY
local SYNC_MUTEX_OPTS = { name = "get_delta", timeout = 0, }
local ngx_log = ngx.log
local ngx_ERR = ngx.ERR


function _M.new(strategy)
  local self = {
    strategy = strategy,
  }

  return setmetatable(self, _MT)
end


function _M:init(manager, is_cp)
  if is_cp then
    manager.callbacks:register("kong.sync.v2.get_delta", function(node_id, version)
      local ok, err = kong.db.clustering_data_planes:upsert({ id = node_id }, {
        last_seen = ngx.time(),
        hostname = node_id,
        ip = "127.0.0.1",
        version = "3.6.0.0",
        sync_status = "normal",
        config_hash = string.format("%032d", version),
      })
      if not ok then
        ngx.log(ngx.ERR, "unable to update clustering data plane status: ", err)
      end

      return self.strategy:get_delta(version)
    end)

  else
    -- DP
    manager.callbacks:register("kong.sync.v2.notify_new_version", function(node_id, version)
      local lmdb_ver = tonumber(declarative.get_current_hash()) or 0
      if lmdb_ver < version then
        return self:sync_once()
      end

      return true
    end)
  end
end


function _M:sync_once(delay)
  local hdl, err = ngx.timer.at(delay or 0, function(premature)
    if premature then
      return
    end

    local res, err = concurrency.with_worker_mutex(SYNC_MUTEX_OPTS, function()
      for i = 1, 2 do
        local delta, err = kong.rpc:call("control_plane", "kong.sync.v2.get_delta",
                             tonumber(declarative.get_current_hash()) or 0)
        if not delta then
          ngx.log(ngx.ERR, "sync get_delta error: ", err)
          return true
        end

        local version = 0

        for _, d in ipairs(delta) do
          if d.row ~= ngx.null then
            assert(kong.db[d.type]:delete({
              id = d.id,
            }))
            assert(kong.db[d.type]:insert(d.row))

          else
            assert(kong.db[d.type]:delete({
              id = d.id,
            }))
          end

          if d.version ~= version then
            version = d.version
            assert(lmdb.set(DECLARATIVE_HASH_KEY, string.format("%032d", version)))
          end
        end

        if version == 0 then
          return true
        end
      end
    end)
    if not res and err ~= "timeout" then
      ngx_log(ngx_ERR, "unable to create worker mutex and sync: ", err)
    end
  end)

  if not hdl then
    return nil, err
  end

  return true
end


return _M
