local _M = {}
local _MT = { __index = _M, }


local txn = require("resty.lmdb.transaction")
local declarative = require("kong.db.declarative")
local constants = require("kong.constants")
local concurrency = require("kong.concurrency")
local isempty = require("table.isempty")
local events = require("kong.runloop.events")
local lrucache = require("resty.lrucache")
local resumable_chunker = require("kong.db.resumable_chunker")
local clustering_utils = require("kong.clustering.utils")


local EMPTY = require("kong.tools.table").EMPTY
local insert_entity_for_txn = declarative.insert_entity_for_txn
local delete_entity_for_txn = declarative.delete_entity_for_txn
local DECLARATIVE_HASH_KEY = constants.DECLARATIVE_HASH_KEY
local CLUSTERING_DATA_PLANES_LATEST_VERSION_KEY = constants.CLUSTERING_DATA_PLANES_LATEST_VERSION_KEY
local CLUSTERING_DATA_PLANES_PAGED_FULL_SYNC_NEXT_TOKEN_KEY = constants.CLUSTERING_DATA_PLANES_PAGED_FULL_SYNC_NEXT_TOKEN_KEY
local DECLARATIVE_DEFAULT_WORKSPACE_KEY = constants.DECLARATIVE_DEFAULT_WORKSPACE_KEY
local DECLARATIVE_EMPTY_CONFIG_HASH = constants.DECLARATIVE_EMPTY_CONFIG_HASH
local CLUSTERING_SYNC_STATUS = constants.CLUSTERING_SYNC_STATUS
local SYNC_MUTEX_OPTS = { name = "get_delta", timeout = 0, }
local MAX_RETRY = 5


local assert = assert
local ipairs = ipairs
local fmt = string.format
local ngx_null = ngx.null
local ngx_log = ngx.log
local ngx_ERR = ngx.ERR
local ngx_INFO = ngx.INFO
local ngx_NOTICE = ngx.NOTICE
local ngx_DEBUG = ngx.DEBUG


local json_encode = clustering_utils.json_encode
local json_decode = clustering_utils.json_decode

-- number of versions behind before a full sync is forced
local DEFAULT_FULL_SYNC_THRESHOLD = 512


function _M.new(strategy, opts)
  opts = opts or EMPTY

  local self = {
    strategy = strategy,
    page_size = opts.page_size,
  }

  return setmetatable(self, _MT)
end


local function inc_sync_result(res)
  return { default = { deltas = res, wipe = false, }, }
end


local function paged_full_sync_payload(page, next_token)
  return {
    default = {
      full_sync = true,
      deltas = page,
      next = next_token and assert(json_encode(next_token)),
    },
  }
end


local function lagacy_full_sync()
  local deltas, err = declarative.export_config_sync()
  if not deltas then
    return nil, err
  end

  return { default = { deltas = deltas, wipe = true, }, }
end


local function page_to_deltas(page)
  local deltas = {}
  for i, entity in ipairs(page) do
    local typ = entity.__type
    entity.__type = nil
    local delta = {
      type = typ,
      entity = entity,
      version = 0, -- pin to the 0 to let DP report itself as not ready
      ws_id = kong.default_workspace,
    }

    deltas[i] = delta
  end

  return deltas
end


local function full_sync(self, workspace)
  local pageable = workspace.pageable
  local next_token = workspace.next

  if not pageable then
    if next_token then
      -- how do I emit a client error?
      return nil, "next_token is set for none pageable DP"
    end

    return lagacy_full_sync()
  end

  local offset, begin_version, end_version
  if next_token then
    local err
    next_token, err = json_decode(next_token)
    if not next_token then
      return nil, "invalid next_token"
    end
    
    offset, begin_version, end_version =
      next_token.offset, next_token.begin_version, next_token.end_version
  else
    begin_version = self.strategy:get_latest_version()
  end

  -- DP finished syncing DB entities. Now trying to catch up with the fix-up deltas
  if not offset then
    if not end_version then
      return nil, "invalid next_token"
    end

    local res, err = self.strategy:get_delta(end_version)
    if not res then
      return nil, err
    end

    -- history is lost. Unable to make a consistent full sync
    if not isempty(res) and res[1].version ~= default_namespace_version + 1 then
      return nil, "history lost, unable to make a consistent full sync"
    end

    return paged_full_sync_payload(res, nil) -- nil next_token marks the end
  end

  local pager = self.pager
  if not pager then
    pager = resumable_chunker.from_db(manager.db, {
      size = self.page_size,
    })
    self.pager = pager
  end

  local page, err, new_offset = pager:fetch(nil, offset)
  if not page then
    return nil, err
  end
  
  local deltas = page_to_deltas(page)

  if not new_offset then
    end_version = self.strategy:get_latest_version()

    -- no changes during the full sync session. No need for fix-up deltas
    if end_version == begin_version then
      return paged_full_sync_payload(deltas, nil)
    end

    -- let DP initiate another call to get fix-up deltas
    return paged_full_sync_payload(deltas, {
      end_version = end_version,
    })
  end

  -- more DB pages to fetch
  return paged_full_sync_payload(deltas, {
    offset = new_offset,
    begin_version = begin_version,
  })
end


function _M:init_cp(manager)
  local purge_delay = manager.conf.cluster_data_plane_purge_delay

  -- number of versions behind before a full sync is forced
  local FULL_SYNC_THRESHOLD = manager.conf.cluster_full_sync_threshold or
                              DEFAULT_FULL_SYNC_THRESHOLD

  -- CP
  -- Method: kong.sync.v2.get_delta
  -- Params: versions: list of current versions of the database
  -- example: { default = { version = 1000, }, }
  manager.callbacks:register("kong.sync.v2.get_delta", function(node_id, current_versions)
    ngx_log(ngx_DEBUG, "[kong.sync.v2] config push (connected client)")

    local rpc_peers
    if kong.rpc then
      rpc_peers = kong.rpc:get_peers()
    end

    local default_namespace = current_versions.default

    if not default_namespace then
      return nil, "default namespace does not exist inside params"
    end

    -- { default = { version = 1000, }, }
    local default_namespace_version = default_namespace.version
    local node_info = assert(kong.rpc:get_peer_info(node_id))

    -- follow update_sync_status() in control_plane.lua
    local ok, err = kong.db.clustering_data_planes:upsert({ id = node_id }, {
      last_seen = ngx.time(),
      hostname = node_id,
      ip = node_info.ip,   -- get the correct ip
      version = node_info.version,    -- get from rpc call
      sync_status = CLUSTERING_SYNC_STATUS.NORMAL,
      config_hash = fmt("%032d", default_namespace_version),
      rpc_capabilities = rpc_peers and rpc_peers[node_id] or {},
    }, { ttl = purge_delay, no_broadcast_crud_event = true, })
    if not ok then
      ngx_log(ngx_ERR, "unable to update clustering data plane status: ", err)
    end

    local latest_version, err = self.strategy:get_latest_version()
    if not latest_version then
      return nil, err
    end

    -- is the node empty? If so, just do a full sync to bring it up to date faster
    if default_namespace_version == 0 or
       (latest_version - default_namespace_version > FULL_SYNC_THRESHOLD) or
       default_namespace.next -- a full-sync session is in progress
    then
      -- we need to full sync because holes are found

      ngx_log(ngx_INFO,
              "[kong.sync.v2] database is empty or too far behind for node_id: ", node_id,
              ", current_version: ", default_namespace_version,
              ", forcing a full sync")

      return full_sync(self, default_namespace)
    end

    -- do we need an incremental sync?

    local res, err = self.strategy:get_delta(default_namespace_version)
    if not res then
      return nil, err
    end

    if isempty(res) then
      -- node is already up to date
      return inc_sync_result(res)
    end

    -- some deltas are returned, are they contiguous?
    if res[1].version == default_namespace_version + 1 then
      -- doesn't wipe dp lmdb, incremental sync
      return inc_sync_result(res)
    end

    -- we need to full sync because holes are found
    -- in the delta, meaning the oldest version is no longer
    -- available

    ngx_log(ngx_INFO,
            "[kong.sync.v2] delta for node_id no longer available: ", node_id,
            ", current_version: ", default_namespace_version,
            ", forcing a full sync")

    return full_sync(self, default_namespace)
  end)
end


function _M:init_dp(manager)
  local kong_shm = ngx.shared.kong
  -- DP
  -- Method: kong.sync.v2.notify_new_version
  -- Params: new_versions: list of namespaces and their new versions, like:
  -- { default = { new_version = 1000, }, }
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
      -- set lastest version to shm
      kong_shm:set(CLUSTERING_DATA_PLANES_LATEST_VERSION_KEY, version)
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


-- check if rpc connection is ready
local function is_rpc_ready()
  -- TODO: find a better way to detect when the RPC layer, including caps list,
  --       has been fully initialized, instead of waiting for up to 5.5 seconds
  for i = 1, 10 do
    local res = kong.rpc:get_peers()

    -- control_plane is ready
    if res["control_plane"] then
      return true
    end

    -- retry later
    ngx.sleep(0.1 * i)
  end
end


local function purge(t)
  t:db_drop(false)
  -- we are at a unready state
  -- consider the config empty
  t:set(DECLARATIVE_HASH_KEY, DECLARATIVE_EMPTY_CONFIG_HASH)
  kong.core_cache:purge()
  kong.cache:purge()
end


local function paginated_error_handle()
  -- a failed full sync.
  local t = txn.begin(512)
  purge(t)
  local ok, err = t:commit()
  if not ok then
    error("failed to reset DB when handling error: " .. err)
  end

  kong_shm:set(CLUSTERING_DATA_PLANES_PAGED_FULL_SYNC_NEXT_TOKEN_KEY, 0)

  -- retry immediately
  return _M:sync_once(0)
end


local function do_sync()
  if not is_rpc_ready() then
    return nil, "rpc is not ready"
  end

  local next_token = kong_shm:get(CLUSTERING_DATA_PLANES_PAGED_FULL_SYNC_NEXT_TOKEN_KEY)

  local version
  if next_token then
    version = 0
  else
    version = tonumber(declarative.get_current_hash()) or 0
  end

  local msg = { default =
                 { version = version,
                   next = next_token,
                   pageable = true,
                 },
               }

  local result, err = kong.rpc:call("control_plane", "kong.sync.v2.get_delta", msg)
  if not result then
    ngx_log(ngx_ERR, "sync get_delta error: ", err)

    if next_token then
      return paginated_error_handle()
    end

    return true
  end

  -- result should look like:
  -- { default = { deltas = { ... }, wipe = true, full_sync_done = false, next_token = ...}, }

  local payload = result.default
  if not payload then
    return nil, "default namespace does not exist inside params"
  end

  local full_sync, first_page, last_page
  if payload.full_sync then
    full_sync = true
    first_page = not next_token and payload.next
    last_page = not payload.next

  elseif payload.wipe then
    -- lagacy full sync
    full_sync, first_page, last_page = true, true, true
  end

  local deltas = payload.deltas

  if isempty(deltas) then
    -- no delta to sync
    return true
  end

  -- we should find the correct default workspace
  -- and replace the old one with it
  local default_ws_changed
  for _, delta in ipairs(deltas) do
    if delta.type == "workspaces" and delta.entity.name == "default" and
      kong.default_workspace ~= delta.entity.id
    then
      kong.default_workspace = delta.entity.id
      default_ws_changed = true
      break
    end
  end
  assert(type(kong.default_workspace) == "string")

  local t = txn.begin(512)

  -- a full sync begins
  if first_page then
    -- reset the lmdb
    purge(t)
    next_token = payload.next
  end

  local db = kong.db

  local version = 0
  local opts = {}
  local crud_events = {}
  local crud_events_n = 0

  -- delta should look like:
  -- { type = ..., entity = { ... }, version = 1, ws_id = ..., }
  for _, delta in ipairs(deltas) do
    local delta_version = delta.version
    local delta_type = delta.type
    local delta_entity = delta.entity
    local ev

    -- delta should have ws_id to generate the correct lmdb key
    -- if entity is workspaceable
    -- set the correct workspace for item
    opts.workspace = delta.ws_id

    if delta_entity ~= nil and delta_entity ~= ngx_null then
      -- upsert the entity
      -- does the entity already exists?
      local old_entity, err = db[delta_type]:select(delta_entity)
      if err then
        return nil, err
      end

      -- If we are purging, we don't need to delete it.
      if old_entity and not full_sync then
        local res, err = delete_entity_for_txn(t, delta_type, old_entity, opts)
        if not res then
          return nil, err
        end
      end

      local res, err = insert_entity_for_txn(t, delta_type, delta_entity, opts)
      if not res then
        return nil, err
      end

      ngx_log(ngx_DEBUG,
              "[kong.sync.v2] update entity",
              ", version: ", delta_version,
              ", type: ", delta_type)

      -- during the full sync, should not emit events
      if not full_sync then
        ev = { delta_type, old_entity and "update" or "create", delta_entity, old_entity, }
      end

    else
      -- delete the entity, opts for getting correct lmdb key
      local old_entity, err = db[delta_type]:select(delta.pk, opts) -- composite key
      if err then
        return nil, err
      end

      -- during the full sync, should not emit events
      if old_entity and not in_full_sync then
        local res, err = delete_entity_for_txn(t, delta_type, old_entity, opts)
        if not res then
          return nil, err
        end
      end

      ngx_log(ngx_DEBUG,
              "[kong.sync.v2] delete entity",
              ", version: ", delta_version,
              ", type: ", delta_type)

      -- delete the entity, opts for getting correct lmdb key
      if not in_full_sync then
        ev = { delta_type, "delete", old_entity, }
      end
    end -- if delta_entity ~= nil and delta_entity ~= ngx_null

    -- during the full sync, should not emit events
    if not full_sync then
      crud_events_n = crud_events_n + 1
      crud_events[crud_events_n] = ev
    end

    -- delta.version should not be nil or ngx.null
    assert(type(delta_version) == "number")

    if delta_version ~= version then
      version = delta_version
    end
  end -- for _, delta

  -- only update the sync version if not in full sync/ full sync done
  if (not full_sync) or last_page then
    -- store current sync version
    t:set(DECLARATIVE_HASH_KEY, fmt("%032d", version))
  end
  
  -- store the correct default workspace uuid
  if default_ws_changed then
    t:set(DECLARATIVE_DEFAULT_WORKSPACE_KEY, kong.default_workspace)
  end

  local ok, err = t:commit()
  if not ok then
    return nil, err
  end

  if full_sync then
    -- the full sync is done
    if last_page then
      kong_shm:set(CLUSTERING_DATA_PLANES_PAGED_FULL_SYNC_NEXT_TOKEN_KEY, nil)
      
      -- Trigger other workers' callbacks like reconfigure_handler.
      --
      -- Full sync could rebuild route, plugins and balancer route, so their
      -- hashes are nil.
      -- Until this point, the dataplane is not ready to serve requests or to
      -- do delta syncs.
      local reconfigure_data = { kong.default_workspace, nil, nil, nil, }
      return events.declarative_reconfigure_notify(reconfigure_data)

    else
      kong_shm:set(CLUSTERING_DATA_PLANES_PAGED_FULL_SYNC_NEXT_TOKEN_KEY, payload.next)

      -- get next page imeediately without releasing the mutex
      -- no need to yield or wait for other workers as the DP is unable to proxy and nothing else
      -- can be done until the full sync is done
      return do_sync()
    end
  end

  -- emit the CRUD events
  -- if in_full_sync, no events should be added into the queue
  for _, event in ipairs(crud_events) do
    -- delta_type, crud_event_type, delta.entity, old_entity
    db[event[1]]:post_crud_event(event[2], event[3], event[4])
  end

  return true
end


local function sync_handler(premature, try_counter, dp_status)
  if premature then
    return
  end

  local res, err = concurrency.with_worker_mutex(SYNC_MUTEX_OPTS, function() do_sync(dp_status) end)
  if not res and err ~= "timeout" then
    ngx_log(ngx_ERR, "unable to create worker mutex and sync: ", err)
  end
end


local sync_once_impl


local function start_sync_once_timer(retry_count)
  local ok, err = ngx.timer.at(0, sync_once_impl, retry_count or 0)
  if not ok then
    return nil, err
  end

  return true
end


function sync_once_impl(premature, retry_count)
  if premature then
    return
  end

  sync_handler()  
  
  local latest_notified_version = ngx.shared.kong:get(CLUSTERING_DATA_PLANES_LATEST_VERSION_KEY)
  local current_version = tonumber(declarative.get_current_hash()) or 0

  if not latest_notified_version then
    ngx_log(ngx_DEBUG, "no version notified yet")
    return
  end

  -- retry if the version is not updated
  if current_version < latest_notified_version then
    retry_count = retry_count or 0
    if retry_count > MAX_RETRY then
      ngx_log(ngx_ERR, "sync_once retry count exceeded. retry_count: ", retry_count)
      return
    end

    return start_sync_once_timer(retry_count + 1)
  end
end


function _M:sync_once(delay)
  return ngx.timer.at(delay or 0, sync_once_impl, 0, self)
end


function _M:sync_every(delay)
  return ngx.timer.every(delay, sync_handler, nil, self)
end


return _M
