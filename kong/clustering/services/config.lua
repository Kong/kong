local utils = require("kong.tools.utils")
local cjson = require("cjson.safe")

local ngx = ngx
local ngx_time = ngx.time
local ngx_log = ngx.log
local INFO = ngx.INFO
local assert = assert
local inflate_gzip = utils.inflate_gzip
local cjson_decode = cjson.decode
local yield = utils.yield

local _M = {}

local _log_prefix = "[wrpc-clustering] "

-- we should move funcitions about config sync here but that would be too large a refactoring.

---- CP part

local function init_config_cp(wrpc_service)
  wrpc_service:import("kong.services.config.v1.config")

  wrpc_service:set_handler("ConfigService.PingCP", function(peer, data)
    local client = peer.client
    if client and client.update_sync_status then
      client.last_seen = ngx_time()
      client.config_hash = data.hash
      client:update_sync_status()
      ngx_log(INFO, _log_prefix, "received ping frame from data plane")
    end
  end)

  wrpc_service:set_handler("ConfigService.ReportMetadata", function(peer, data)
    local client = peer.client
    if client then
      ngx_log(INFO, _log_prefix, "received initial metadata package from client: ", client.dp_id)
      client.basic_info = data
      client.basic_info_semaphore:post()
    end
    return {
      ok = "done",
    }
  end)
end


---- DP part

local function init_config_dp(service)
  service:import("kong.services.config.v1.config")
  service:set_handler("ConfigService.SyncConfig", function(peer, data)
    -- yield between steps to prevent long delay
    if peer.config_semaphore then
      local json_config = assert(inflate_gzip(data.config))
      yield()
      peer.config_obj.next_config = assert(cjson_decode(json_config))
      yield()

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

function _M.init(register)
  register("config", {
    { version = "v1", description = "The configuration synchronizing service. (JSON and Gzip)" },
  }, init_config_dp, init_config_cp)
end

return _M