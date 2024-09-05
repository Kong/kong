local _M = {}
local _MT = { __index = _M, }


local semaphore = require("ngx.semaphore")
local lmdb = require("resty.lmdb")
local txn = require("resty.lmdb.transaction")
local declarative = require("kong.db.declarative")
local constants = require("kong.constants")
local concurrency = require("kong.concurrency")


local DECLARATIVE_HASH_KEY = constants.DECLARATIVE_HASH_KEY
local SYNC_MUTEX_OPTS = { name = "get_delta", timeout = 0, }
local ngx_log = ngx.log
local ngx_ERR = ngx.ERR
local ngx_INFO = ngx.INFO
local ngx_DEBUG = ngx.DEBUG


function _M.new(strategy)
  local self = {
    strategy = strategy,
  }

  return setmetatable(self, _MT)
end


function _M:init(manager, is_cp)
  if is_cp then
    -- CP
    -- Method: kong.sync.v2.get_delta
    -- Params: versions: list of current versions of the database
    -- { { namespace = "default", current_version = 1000, }, }
    manager.callbacks:register("kong.sync.v2.get_delta", function(node_id, current_versions)
      local rpc_peers
      if kong.rpc then
        rpc_peers = kong.rpc:get_peers()
      end

      local ok, err = kong.db.clustering_data_planes:upsert({ id = node_id }, {
        last_seen = ngx.time(),
        hostname = node_id,
        ip = "127.0.7.1",
        version = "3.7.0.0",
        sync_status = "normal",
        config_hash = string.format("%032d", version),
        rpc_capabilities = rpc_peers and rpc_peers[node_id] or {},
      })
      if not ok then
        ngx.log(ngx.ERR, "unable to update clustering data plane status: ", err)
      end

      for _, current_version in ipairs(current_versions) do
        if current_version.namespace == "default" then
          local res, err = self.strategy:get_delta(current_version.current_version)
          if not res then
            return nil, err
          end

          if #res == 0 then
            ngx_log(ngx_DEBUG, "[kong.sync.v2] no delta for node_id: ", node_id,
                    ", current_version: ", current_version.current_version,
                    ", node is already up to date" )
            return { { namespace = "default", deltas = res, wipe = false, }, }
          end

          -- some deltas are returned, are they contiguous?
          if res[1].version ~= current_version.current_version + 1 then
            -- we need to full sync because holes are found

            ngx_log(ngx_INFO, "[kong.sync.v2] delta for node_id no longer available: ", node_id,
                    ", current_version: ", current_version.current_version,
                    ", forcing a full sync")


            local deltas err = declarative.export_config_sync()
            if not deltas then
              return nil, err
            end

            return { { namespace = "default", deltas = deltas, wipe = true, }, }
          end

          return { { namespace = "default", deltas = res, wipe = false, }, }
        end
      end

      return nil, "default namespace does not exist"
    end)

  else
    -- DP
    -- Method: kong.sync.v2.notify_new_version
    -- Params: new_versions: list of namespaces and their new versions, like:
    -- { { namespace = "default", new_version = 1000, }, }
    manager.callbacks:register("kong.sync.v2.notify_new_version", function(node_id, new_versions)
      -- currently only default is supported, and anything else is ignored
      for _, new_version in ipairs(new_versions) do
        if new_version.namespace == "default" then
          local version = new_version.new_version
          if not version then
            return nil, "'new_version' key does not exist"
          end

          local lmdb_ver = tonumber(declarative.get_current_hash()) or 0
          if lmdb_ver < version then
            return self:sync_once()
          end

          return true
        end
      end

      return nil, "default namespace does not exist inside params"
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
        local ns_deltas, err = kong.rpc:call("control_plane", "kong.sync.v2.get_delta",
                             tonumber(declarative.get_current_hash()) or 0)
        if not ns_deltas then
          ngx.log(ngx.ERR, "sync get_delta error: ", err)
          return true
        end

        local version = 0

        for _, ns_delta in ipairs(ns_deltas) do
          if ns_delta.namespace == "default" then
            local t = txn.begin(512)

            if ns_delta.wipe then
              t:db_drop(false)

              local ok, err = t:commit()
              if not ok then
                return nil, err
              end

              t:reset()
            end

            for _, delta in ipairs(ns_delta.delta) do
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

              if delta.version ~= version then
                version = delta.version
              end
            end

            t:set(DECLARATIVE_HASH_KEY, string.format("%032d", version))
            local ok, err = t:commit()
            if not ok then
              return nil, err
            end

            if ns_delta.wipe then
              kong.core_cache:purge()
              kong.cache:purge()
            end

            return true
          end
        end

        return nil, "default namespace does not exist inside params"
      end

      return true
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
