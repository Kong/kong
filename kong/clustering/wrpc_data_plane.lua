local semaphore = require("ngx.semaphore")
local declarative = require("kong.db.declarative")
local wrpc = require("kong.tools.wrpc")
local config_helper = require("kong.clustering.config_helper")
local clustering_utils = require("kong.clustering.utils")
local constants = require("kong.constants")
local wrpc_proto = require("kong.tools.wrpc.proto")
local cjson = require("cjson.safe")
local utils = require("kong.tools.utils")
local negotiation = require("kong.clustering.services.negotiation")
local init_negotiation_client = negotiation.init_negotiation_client
local negotiate = negotiation.negotiate
local get_negotiated_service = negotiation.get_negotiated_service

local assert = assert
local setmetatable = setmetatable
local tonumber = tonumber
local math = math
local traceback = debug.traceback
local xpcall = xpcall
local ngx = ngx
local ngx_log = ngx.log
local ngx_sleep = ngx.sleep
local exiting = ngx.worker.exiting
local inflate_gzip = utils.inflate_gzip
local cjson_decode = cjson.decode
local yield = utils.yield


local ngx_ERR = ngx.ERR
local ngx_INFO = ngx.INFO
local ngx_NOTICE = ngx.NOTICE
local PING_INTERVAL = constants.CLUSTERING_PING_INTERVAL
local _log_prefix = "[wrpc-clustering] "
local DECLARATIVE_EMPTY_CONFIG_HASH = constants.DECLARATIVE_EMPTY_CONFIG_HASH
local accept_table =  { accepted = true }


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

  return setmetatable(self, _MT)
end

local communicate

function _M:init_worker(plugins_list)
  -- ROLE = "data_plane"

  self.plugins_list = plugins_list

  if ngx.worker.id() == 0 then
    communicate(self)
  end
end


local function init_config_service(service)
  service:import("kong.services.config.v1.config")
  service:set_handler("ConfigService.SyncConfig", function(peer, data)
    -- yield between steps to prevent long delay
    if peer.config_semaphore then
      peer.config_obj.next_data = data
      if peer.config_semaphore:count() <= 0 then
        -- the following line always executes immediately after the `if` check
        -- because `:count` will never yield, end result is that the semaphore
        -- count is guaranteed to not exceed 1
        peer.config_semaphore:post()
      end
    end
    return accept_table
  end)
end

local wrpc_services
local function get_services()
  if not wrpc_services then
    wrpc_services = wrpc_proto.new()
    init_negotiation_client(wrpc_services)
    init_config_service(wrpc_services)
  end

  return wrpc_services
end

-- we should have only 1 dp peer at a time
-- this is to prevent leaking (of objects and threads)
-- when communicate_impl fail to reach error handling
local peer

local function communicate_impl(dp)
  local conf = dp.conf

  local log_suffix = " [" .. conf.cluster_control_plane .. "]"

  local c, uri, err = clustering_utils.connect_cp(
                        "/v1/wrpc", conf, dp.cert, dp.cert_key,
                        "wrpc.konghq.com")
  if not c then
    error("connection to control plane " .. uri .." broken: " .. err)
  end

  local config_semaphore = semaphore.new(0)

  -- prevent leaking
  if peer and not peer.closing then
    peer:close()
  end
  peer = wrpc.new_peer(c, get_services())

  peer.config_semaphore = config_semaphore
  peer.config_obj = dp
  peer:spawn_threads()

  do
    local ok, err = negotiate(peer)
    if not ok then
      error(err)
    end
  end

  do
    local version, msg = get_negotiated_service("config")
    if not version then
      error("config sync service not supported: " .. msg)
    end
    local resp, err = peer:call_async("ConfigService.ReportMetadata", { plugins = dp.plugins_list })

    -- if resp is not nil, it must be table
    if not resp or not resp.ok then
      error("Couldn't report basic info to CP: " .. (resp and resp.error or err))
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

        local data = dp.next_data
        if data then
          local config_version = tonumber(data.version)
          if config_version > last_config_version then
            local config_table = assert(inflate_gzip(data.config))
            yield()
            config_table = assert(cjson_decode(config_table))
            yield()
            ngx_log(ngx_INFO, _log_prefix, "received config #", config_version, log_suffix)

            local pok, res
            pok, res, err = xpcall(config_helper.update, traceback, dp.declarative_config,
                                   config_table, data.config_hash, data.hashes)
            if pok then
              last_config_version = config_version
              if not res then
                ngx_log(ngx_ERR, _log_prefix, "unable to update running config: ", err)
              end

            else
              ngx_log(ngx_ERR, _log_prefix, "unable to update running config: ", res)
            end

            if dp.next_data == data then
              dp.next_data = nil
            end
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
  peer:close()

  if not ok then
   error(err)

  elseif perr then
    error(perr)
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
end

local communicate_loop

function communicate(dp, reconnection_delay)
  return ngx.timer.at(reconnection_delay or 0, communicate_loop, dp)
end

function communicate_loop(premature, dp)
  if premature then
    -- worker wants to exit
    return
  end

  local ok, err = pcall(communicate_impl, dp)

  if not ok then
    ngx_log(ngx_ERR, err)
  end

  -- retry connection
  local reconnection_delay = math.random(5, 10)
  ngx_log(ngx_NOTICE, " (retrying after " .. reconnection_delay .. " seconds)")
  if not exiting() then
    communicate(dp, reconnection_delay)
  end
end

return _M
