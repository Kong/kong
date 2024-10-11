local _M = {}
local _MT = { __index = _M, }


local txn = require("resty.lmdb.transaction")
local declarative = require("kong.db.declarative")
local constants = require("kong.constants")
local concurrency = require("kong.concurrency")


local insert_entity_for_txn = declarative.insert_entity_for_txn
local delete_entity_for_txn = declarative.delete_entity_for_txn
local DECLARATIVE_HASH_KEY = constants.DECLARATIVE_HASH_KEY
local CLUSTERING_SYNC_STATUS = constants.CLUSTERING_SYNC_STATUS
local SYNC_MUTEX_OPTS = { name = "get_delta", timeout = 0, }


local pairs = pairs
local ipairs = ipairs
local fmt = string.format
local ngx_null = ngx.null
local ngx_log = ngx.log
local ngx_ERR = ngx.ERR
local ngx_INFO = ngx.INFO
local ngx_DEBUG = ngx.DEBUG


-- number of versions behind before a full sync is forced
local FULL_SYNC_THRESHOLD = 512


function _M.new(strategy)
  local self = {
    strategy = strategy,
  }

  return setmetatable(self, _MT)
end


function _M:init_cp(manager)
  -- CP
  -- Method: kong.sync.v2.get_delta
  -- Params: versions: list of current versions of the database
  -- { { namespace = "default", version = 1000, }, }
  local purge_delay = manager.conf.cluster_data_plane_purge_delay

  local function gen_delta_result(res, wipe)
    return { default = { deltas = res, wipe = wipe, }, }
  end

  manager.callbacks:register("kong.sync.v2.get_delta", function(node_id, current_versions)
    ngx_log(ngx_DEBUG, "[kong.sync.v2] config push (connected client)")

    local rpc_peers
    if kong.rpc then
      rpc_peers = kong.rpc:get_peers()
    end

    local default_namespace
    for namespace, v in pairs(current_versions) do
      if namespace == "default" then
        default_namespace = v
        break
      end
    end

    if not default_namespace then
      return nil, "default namespace does not exist inside params"
    end

    -- { { namespace = "default", version = 1000, }, }
    local default_namespace_version = default_namespace.version

    -- XXX TODO: follow update_sync_status() in control_plane.lua
    local ok, err = kong.db.clustering_data_planes:upsert({ id = node_id }, {
      last_seen = ngx.time(),
      hostname = node_id,
      ip = kong.rpc:get_peer_ip(node_id),   -- try to get the correct ip
      version = "3.8.0.0",    -- XXX TODO: get from rpc call
      sync_status = CLUSTERING_SYNC_STATUS.NORMAL,
      config_hash = fmt("%032d", default_namespace_version),
      rpc_capabilities = rpc_peers and rpc_peers[node_id] or {},
    }, { ttl = purge_delay })
    if not ok then
      ngx_log(ngx_ERR, "unable to update clustering data plane status: ", err)
    end

    local latest_version, err = self.strategy:get_latest_version()
    if not latest_version then
      return nil, err
    end

    -- is the node empty? If so, just do a full sync to bring it up to date faster
    if default_namespace_version == 0 or
       latest_version - default_namespace_version > FULL_SYNC_THRESHOLD
    then
      -- we need to full sync because holes are found

      ngx_log(ngx_INFO,
              "[kong.sync.v2] database is empty or too far behind for node_id: ", node_id,
              ", current_version: ", default_namespace_version,
              ", forcing a full sync")


      local deltas, err = declarative.export_config_sync()
      if not deltas then
        return nil, err
      end

      -- wipe dp lmdb, full sync
      return gen_delta_result(deltas, true)
    end

    local res, err = self.strategy:get_delta(default_namespace_version)
    if not res then
      return nil, err
    end

    if #res == 0 then
      ngx_log(ngx_DEBUG,
              "[kong.sync.v2] no delta for node_id: ", node_id,
              ", current_version: ", default_namespace_version,
              ", node is already up to date" )
      return gen_delta_result(res, false)
    end

    -- some deltas are returned, are they contiguous?
    if res[1].version == default_namespace.version + 1 then
      -- doesn't wipe dp lmdb, incremental sync
      return gen_delta_result(res, false)
    end

    -- we need to full sync because holes are found
    -- in the delta, meaning the oldest version is no longer
    -- available

    ngx_log(ngx_INFO,
            "[kong.sync.v2] delta for node_id no longer available: ", node_id,
            ", current_version: ", default_namespace_version,
            ", forcing a full sync")

    local deltas, err = declarative.export_config_sync()
    if not deltas then
      return nil, err
    end

    -- wipe dp lmdb, full sync
    return gen_delta_result(deltas, true)
  end)
end


function _M:init_dp(manager)
  -- DP
  -- Method: kong.sync.v2.notify_new_version
  -- Params: new_versions: list of namespaces and their new versions, like:
  -- { { new_version = 1000, }, }, possible field: namespace = "default"
  manager.callbacks:register("kong.sync.v2.notify_new_version", function(node_id, new_versions)
    -- TODO: currently only default is supported, and anything else is ignored
    local default_new_version = new_versions.default
    if not default_new_version then
      return nil, "default namespace does not exist inside params"
    end

    local version = default_new_version.new_version
    if not version then
      return nil, "'new_version' key does not exist"
    end

    local lmdb_ver = tonumber(declarative.get_current_hash()) or 0
    if lmdb_ver < version then
      return self:sync_once()
    end

    return true
  end)
end


function _M:init(manager, is_cp)
  if is_cp then
    self:init_cp(manager)
  else
    self:init_dp(manager)
  end
end


local function do_sync(premature)
  if premature then
    return
  end

  local res, err = concurrency.with_worker_mutex(SYNC_MUTEX_OPTS, function()
    -- here must be 2 times
    for _ = 1, 2 do
      local ns_deltas, err = kong.rpc:call("control_plane", "kong.sync.v2.get_delta",
                                           { default =
                                             { version =
                                               tonumber(declarative.get_current_hash()) or 0,
                                             },
                                           })
      if not ns_deltas then
        ngx_log(ngx_ERR, "sync get_delta error: ", err)
        return true
      end

      local ns_delta

      for namespace, delta in pairs(ns_deltas) do
        if namespace == "default" then
          ns_delta = delta
          break   -- should we break here?
        end
      end

      if not ns_delta then
        return nil, "default namespace does not exist inside params"
      end

      if #ns_delta.deltas == 0 then
        ngx_log(ngx_DEBUG, "no delta to sync")
        return true
      end

      local t = txn.begin(512)

      if ns_delta.wipe then
        t:db_drop(false)
      end

      local db = kong.db

      local version = 0
      local crud_events = {}
      local crud_events_n = 0

      for _, delta in ipairs(ns_delta.deltas) do
        local delta_type = delta.type
        local delta_row = delta.row
        local ev

        if delta_row ~= ngx_null then
          -- upsert the entity
          -- does the entity already exists?
          local old_entity, err = db[delta_type]:select(delta_row)
          if err then
            return nil, err
          end

          local crud_event_type = "create"

          if old_entity then
            local res, err = delete_entity_for_txn(t, delta_type, old_entity, nil)
            if not res then
              return nil, err
            end

            crud_event_type = "update"
          end

          local res, err = insert_entity_for_txn(t, delta_type, delta_row, nil)
          if not res then
            return nil, err
          end

          ev = { delta_type, crud_event_type, delta_row, old_entity, }

        else
          -- delete the entity
          local old_entity, err = kong.db[delta_type]:select({ id = delta.id, }) -- TODO: composite key
          if err then
            return nil, err
          end

          if old_entity then
            local res, err = delete_entity_for_txn(t, delta_type, old_entity, nil)
            if not res then
              return nil, err
            end
          end

          ev = { delta_type, "delete", old_entity, }
        end

        crud_events_n = crud_events_n + 1
        crud_events[crud_events_n] = ev

        -- XXX TODO: could delta.version be nil or ngx.null
        if type(delta.version) == "number" and delta.version ~= version then
          version = delta.version
        end
      end

      t:set(DECLARATIVE_HASH_KEY, fmt("%032d", version))
      local ok, err = t:commit()
      if not ok then
        return nil, err
      end

      if ns_delta.wipe then
        kong.core_cache:purge()
        kong.cache:purge()

      else
        for _, event in ipairs(crud_events) do
          -- delta_type, crud_event_type, delta.row, old_entity
          db[event[1]]:post_crud_event(event[2], event[3], event[4])
        end
      end
    end -- for _, delta

    return true
  end)
  if not res and err ~= "timeout" then
    ngx_log(ngx_ERR, "unable to create worker mutex and sync: ", err)
  end
end


function _M:sync_once(delay)
  local hdl, err = ngx.timer.at(delay or 0, do_sync)

  if not hdl then
    return nil, err
  end

  return true
end


function _M:sync_every(delay)
  local hdl, err = ngx.timer.every(delay, do_sync)

  if not hdl then
    return nil, err
  end

  return true
end


return _M
