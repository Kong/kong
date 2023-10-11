-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local declarative = require("kong.db.declarative")
local kong_version = require("kong.meta").version
local cjson = require("cjson")
local utils = require("kong.tools.utils")
local clustering_utils = require("kong.clustering.utils")
local config_helper = require("kong.clustering.config_helper")
local semaphore = require("ngx.semaphore")
local DECLARATIVE_EMPTY_CONFIG_HASH = require("kong.constants").DECLARATIVE_EMPTY_CONFIG_HASH


local yield = utils.yield
local ngx_log = ngx.log
local ngx_ERR = ngx.ERR
local ngx_INFO = ngx.INFO
local ngx_DEBUG = ngx.DEBUG
local json_decode = cjson.decode
local json_encode = cjson.encode
local semaphore_new = semaphore.new
local type = type
local error = error
local assert = assert


local FALLBACK_CONFIG_PREFIX = "[fallback config] "
local WAIT_TIMEOUT = 60
-- maximum 1 config sync per 60 seconds
local EXPORT_DELAY = 60
local declarative_config
local storage
local export_smph
-- when config is exported by control plane, we directly pass the config exported by config sync
-- to avoid exporting the config twice
local exported_config


local _M = {}


function _M.init(conf)
  local url = assert(conf.cluster_fallback_config_storage)
  local module

  if url:sub(1, 5) == "s3://" then
    module = require("kong.clustering.config_sync_backup.strategies.s3")

  elseif url:sub(1, 6) == "gcs://" then
    module = require("kong.clustering.config_sync_backup.strategies.gcs")

  else
    -- this should be caught by conf_loader
    error("unsupported storage: " .. url .. ".")
  end

  storage = module.new(kong_version, url)
end


local function export_config_impl()
  -- Do not yield before this. otherwise it may be overwritten by another export
  local config_table = exported_config
  local err

  -- of course we can cache JSON encoded config, but when we go back with JSON-Websocket,
  -- we won't have config JSON encoded in the same format
  if not config_table then
    ngx_log(ngx_DEBUG, FALLBACK_CONFIG_PREFIX, "encoding config")
    config_table, err = declarative.export_config()
  end

  if not config_table then
    return nil, "failed to export config: " .. tostring(err)
  end

  yield()

  ngx_log(ngx_DEBUG, FALLBACK_CONFIG_PREFIX, "encoding config")

  local encoded, err = json_encode(config_table)
  if not encoded then
    return nil, "failed to encode config: " .. tostring(err)
  end

  yield()

  ngx_log(ngx_DEBUG, FALLBACK_CONFIG_PREFIX, "sending config to fallback storage")

  local ok, err = storage:backup_config(encoded)
  if not ok then
    return nil, err
  end

  return true
end


local export_config_loop do
  -- concurrent calls to this function are safe
  local function export_config_timer(premature)
    if premature then
      return
    end

    if not storage then
      -- we should have already logged an error about this
      return
    end

    local ok, err = export_smph:wait(WAIT_TIMEOUT)
    if not ok and err ~= "timeout" then
      ngx_log(ngx_ERR, FALLBACK_CONFIG_PREFIX, "failed to acquire semaphore: ", err)
    end

    if not ok then
      return export_config_loop()
    end

    ngx_log(ngx_INFO, FALLBACK_CONFIG_PREFIX, "exporting config to fallback storage")

    ok, err = export_config_impl()
    if ok then
      ngx_log(ngx_INFO, FALLBACK_CONFIG_PREFIX, "successfully exported config to fallback storage")

    else
      ngx_log(ngx_ERR, FALLBACK_CONFIG_PREFIX, "failed to export config to fallback storage: " .. err)
    end

    export_config_loop(EXPORT_DELAY)
  end


  function export_config_loop(delay)
    local ok, err
    local tries = 0

    repeat
      ok, err = ngx.timer.at(delay or 0, export_config_timer)
      if err then
        if err == "process exiting" then
          return
        end

        ngx_log(ngx_ERR, FALLBACK_CONFIG_PREFIX, "failed to create timer: ", err)
      end

      tries = tries + 1
      -- yield so we have a chance that old timers exited
      yield()
    until ok or tries > 10
  end
end


-- this function must only be called from 0 worker
-- this function never throw errors
local function export_config(exported)
  assert(clustering_utils.is_dp_worker_process(), "fallback config export_config should only be called at worker #0 or privileged agent")

  -- only exporters has a timer to answer export_smph. but we mute this function
  if not kong.configuration.cluster_fallback_config_export then
    return
  end

  ngx_log(ngx_DEBUG, FALLBACK_CONFIG_PREFIX,
          "new config export call", exported and " with exported config" or "")
  -- the order matters here, otherwise it may export outdated config
  exported_config = exported
  if export_smph and export_smph:count() <= 0 then
    export_smph:post()
  end
end


_M.export_config = export_config


local function fetch_and_apply_config()
  if not storage then
    error("no fallback storage configured")
  end

  local encoded = assert(storage:fetch_config())

  ngx_log(ngx_DEBUG, FALLBACK_CONFIG_PREFIX, "fetched config from fallback storage")

  local config_table
  if type(encoded) == "string" then
    config_table = assert(json_decode(encoded))
    yield()

  elseif type(encoded) == "table" then
    config_table = encoded

  else
    error(FALLBACK_CONFIG_PREFIX .. "invalid config type: " .. type(encoded))
  end

  ngx_log(ngx_DEBUG, FALLBACK_CONFIG_PREFIX, "decoded config")

  assert(config_helper.update(declarative_config, config_table))

  ngx_log(ngx_DEBUG, FALLBACK_CONFIG_PREFIX, "successfully applied config from fallback storage")
end


-- this function never throw errors
local function export(conf)
  EXPORT_DELAY = conf.cluster_fallback_config_export_delay or 60

  export_smph = semaphore_new(0)
  export_config_loop()

  -- initial export for control plane start up
  if conf.role == "control_plane" then
    ngx_log(ngx_DEBUG, FALLBACK_CONFIG_PREFIX, "first time export for control plane")
    export_config()
  end
end


-- We only import if the first time to connect to the CP fails. If we fail, we don't try again.
-- It's possible that the config sync timer runs again before last import finishes.
local imported = false
-- this function never throw errors
function _M.import(conf)
  assert(conf.role == "data_plane", "only data plane can call import fallback config")

  if imported then
    return
  end

  imported = true

  if not conf.cluster_fallback_config_import then
    return
  end

  local config_hash = declarative.get_current_hash()

  -- we have LMDB cache
  if config_hash and config_hash ~= DECLARATIVE_EMPTY_CONFIG_HASH then
    return
  end

  ngx_log(ngx_INFO, FALLBACK_CONFIG_PREFIX, "control_plane not connected. Fetching config from fallback storage")

  local ok, err = pcall(fetch_and_apply_config)

  if ok then
    ngx_log(ngx_INFO, FALLBACK_CONFIG_PREFIX, "fallback config applied")

  else
    ngx_log(ngx_ERR, FALLBACK_CONFIG_PREFIX, "failed to fetch config from backup storage: ", err)
  end
end


function _M.init_worker(conf, backup_role)
  if not clustering_utils.is_dp_worker_process() then
    return
  end

  local ok, err = pcall(storage.init_worker)
  if not ok then
    ngx_log(ngx_ERR, FALLBACK_CONFIG_PREFIX, "error when initializing backup storage for fallback config: ", err)
    return
  end

  if backup_role == "exporter" then
    export(conf)

  elseif backup_role == "importer" then
    declarative_config = assert(kong.db.declarative_config,
                                "kong.db.declarative_config was not initialized")

  else
    ngx_log(ngx_ERR, FALLBACK_CONFIG_PREFIX, "unknown role: ", backup_role)
  end
end


return _M

