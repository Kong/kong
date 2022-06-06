-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

-- XXX EE
local ee = require "kong.enterprise_edition.clustering.data_plane"
-- EE

local semaphore = require("ngx.semaphore")
local declarative = require("kong.db.declarative")
local protobuf = require("kong.tools.protobuf")
local wrpc = require("kong.tools.wrpc")
local config_helper = require("kong.clustering.config_helper")
local clustering_utils = require("kong.clustering.utils")
local constants = require("kong.constants")
local wrpc_proto = require("kong.tools.wrpc.proto")
local assert = assert
local setmetatable = setmetatable
local math = math
local xpcall = xpcall
local ngx = ngx
local ngx_log = ngx.log
local ngx_sleep = ngx.sleep
local exiting = ngx.worker.exiting


local ngx_ERR = ngx.ERR
local ngx_INFO = ngx.INFO
local PING_INTERVAL = constants.CLUSTERING_PING_INTERVAL
local _log_prefix = "[wrpc-clustering] "
local DECLARATIVE_EMPTY_CONFIG_HASH = constants.DECLARATIVE_EMPTY_CONFIG_HASH

local CONFIG_CACHE = ngx.config.prefix() .. "/config.cache.json.gz"
--- XXX EE
local CONFIG_CACHE_ENCRYPTED = ngx.config.prefix() .. "/.config.cache.jwt"
--- EE

local _M = {
  DPCP_CHANNEL_NAME = "DP-CP_config",
}
local _MT = { __index = _M, }

function _M.new(conf, cert, cert_key)
  local self = {
    declarative_config = declarative.new_config(conf),
    conf = conf,
    cert = cert,
    cert_key = cert_key,
  }

  --- XXX EE
  local config_cache_path = parent.conf.data_plane_config_cache_path
  local config_cache_mode = parent.conf.data_plane_config_cache_mode
  if config_cache_mode == "unencrypted" then
    self.config_cache = config_cache_path or CONFIG_CACHE

  elseif config_cache_mode == "encrypted" then
    self.config_cache = config_cache_path or CONFIG_CACHE_ENCRYPTED
    self.encode_config = ee.encode_config
    self.decode_config = ee.decode_config
  end
  --- EE

  return setmetatable(self, _MT)
end


function _M:init_worker(plugins_list)
  -- ROLE = "data_plane"

  self.plugins_list = plugins_list

  if ngx.worker.id() == 0 then
    assert(ngx.timer.at(0, function(premature)
      self:communicate(premature)
    end))
  end
end


local wrpc_config_service
local function get_config_service()
  if not wrpc_config_service then
    wrpc_config_service = wrpc_proto.new()
    wrpc_config_service:import("kong.services.config.v1.config")
    wrpc_config_service:set_handler("ConfigService.SyncConfig", function(peer, data)
      if peer.config_semaphore then
        if data.config.plugins then
          for _, plugin in ipairs(data.config.plugins) do
            plugin.config = protobuf.pbunwrap_struct(plugin.config)
          end
        end
        data.config._format_version = data.config.format_version
        data.config.format_version = nil

        peer.config_obj.next_config = data.config
        peer.config_obj.next_hash = data.config_hash
        peer.config_obj.next_hashes = data.hashes
        peer.config_obj.next_config_version = tonumber(data.version)
        if peer.config_semaphore:count() <= 0 then
          -- the following line always executes immediately after the `if` check
          -- because `:count` will never yield, end result is that the semaphore
          -- count is guaranteed to not exceed 1
          peer.config_semaphore:post()
        end
      end
      return { accepted = true }
    end)
  end

  return wrpc_config_service
end

function _M:communicate(premature)
  if premature then
    -- worker wants to exit
    return
  end

  local conf = self.conf

  local log_suffix = " [" .. conf.cluster_control_plane .. "]"
  local reconnection_delay = math.random(5, 10)

  local c, uri, err = clustering_utils.connect_cp(
                        "/v1/wrpc", conf, self.cert, self.cert_key,
                        "wrpc.konghq.com")
  if not c then
    ngx_log(ngx_ERR, _log_prefix, "connection to control plane ", uri, " broken: ", err,
                 " (retrying after ", reconnection_delay, " seconds)", log_suffix)

    assert(ngx.timer.at(reconnection_delay, function(premature)
      self:communicate(premature)
    end))
    return
  end

  local config_semaphore = semaphore.new(0)
  local peer = wrpc.new_peer(c, get_config_service(), { channel = self.DPCP_CHANNEL_NAME })

  peer.config_semaphore = config_semaphore
  peer.config_obj = self
  peer:spawn_threads()

  do
    local resp, err = peer:call_async("ConfigService.ReportMetadata", { plugins = self.plugins_list })

    -- if resp is not nil, it must be table
    if not resp or not resp.ok then
      ngx_log(ngx_ERR, _log_prefix, "Couldn't report basic info to CP: ", resp and resp.error or err)
      assert(ngx.timer.at(reconnection_delay, function(premature)
        self:communicate(premature)
      end))
    end
  end

  -- Here we spawn two threads:
  --
  -- * config_thread: it grabs a received declarative config and apply it
  --                  locally. In addition, this thread also persists the
  --                  config onto the local file system
  -- * ping_thread: performs a ConfigService.PingCP call periodically.

  local config_exit
  local last_config_version = -1

  local config_thread = ngx.thread.spawn(function()
    while not exiting() and not config_exit do
      local ok, err = config_semaphore:wait(1)
      if ok then
        if peer.semaphore == config_semaphore then
          peer.semaphore = nil
          config_semaphore = nil
        end
        local config_table = self.next_config
        local config_hash  = self.next_hash
        local config_version = self.next_config_version
        local hashes = self.next_hashes
        if config_table and config_version > last_config_version then
          ngx_log(ngx_INFO, _log_prefix, "received config #", config_version, log_suffix)

          local pok, res
          pok, res, err = xpcall(config_helper.update, debug.traceback,
                                 self.declarative_config, config_table, config_hash, hashes)
          if pok then
            last_config_version = config_version
            if not res then
              ngx_log(ngx_ERR, _log_prefix, "unable to update running config: ", err)
            end

          else
            ngx_log(ngx_ERR, _log_prefix, "unable to update running config: ", res)
          end

          if self.next_config == config_table then
            self.next_config = nil
            self.next_hash = nil
            self.next_hashes = nil
          end
        end

      elseif err ~= "timeout" then
        ngx_log(ngx_ERR, _log_prefix, "semaphore wait error: ", err)
      end
    end
  end)

  local ping_thread = ngx.thread.spawn(function()
    while not exiting() do
      local hash = declarative.get_current_hash()

      if hash == true then
        hash = DECLARATIVE_EMPTY_CONFIG_HASH
      end
      assert(peer:call_no_return("ConfigService.PingCP", { hash = hash }))
      ngx_log(ngx_INFO, _log_prefix, "sent ping", log_suffix)

      for _ = 1, PING_INTERVAL do
        ngx_sleep(1)
        if exiting() or peer.closing then
          return
        end
      end
    end
  end)

  local ok, err, perr = ngx.thread.wait(ping_thread, config_thread)

  ngx.thread.kill(ping_thread)
  c:close()

  if not ok then
    ngx_log(ngx_ERR, _log_prefix, err, log_suffix)

  elseif perr then
    ngx_log(ngx_ERR, _log_prefix, perr, log_suffix)
  end

  -- the config thread might be holding a lock if it's in the middle of an
  -- update, so we need to give it a chance to terminate gracefully
  config_exit = true
  ok, err, perr = ngx.thread.wait(config_thread)

  if not ok then
    ngx_log(ngx_ERR, _log_prefix, err, log_suffix)

  elseif perr then
    ngx_log(ngx_ERR, _log_prefix, perr, log_suffix)
  end

  if not exiting() then
    assert(ngx.timer.at(reconnection_delay, function(premature)
      self:communicate(premature)
    end))
  end
end

return _M
