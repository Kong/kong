local _M = {}
local _MT = { __index = _M, }


local semaphore = require("ngx.semaphore")
local cjson = require("cjson.safe")
local config_helper = require("kong.clustering.config_helper")
local clustering_utils = require("kong.clustering.utils")
local declarative = require("kong.db.declarative")
local constants = require("kong.constants")
local pl_stringx = require("pl.stringx")
local inspect = require("inspect")

local assert = assert
local setmetatable = setmetatable
local math = math
local tostring = tostring
local sub = string.sub
local ngx = ngx
local ngx_log = ngx.log
local ngx_sleep = ngx.sleep
local cjson_decode = cjson.decode
local cjson_encode = cjson.encode
local exiting = ngx.worker.exiting
local ngx_time = ngx.time
local inflate_gzip = require("kong.tools.gzip").inflate_gzip
local yield = require("kong.tools.yield").yield


local ngx_ERR = ngx.ERR
local ngx_INFO = ngx.INFO
local ngx_DEBUG = ngx.DEBUG
local ngx_WARN = ngx.WARN
local ngx_NOTICE = ngx.NOTICE
local PING_INTERVAL = constants.CLUSTERING_PING_INTERVAL
local PING_WAIT = PING_INTERVAL * 1.5
local _log_prefix = "[clustering] "
local DECLARATIVE_EMPTY_CONFIG_HASH = constants.DECLARATIVE_EMPTY_CONFIG_HASH

local endswith = pl_stringx.endswith

local function is_timeout(err)
  return err and sub(err, -7) == "timeout"
end


function _M.new(clustering)
  assert(type(clustering) == "table",
         "kong.clustering is not instantiated")

  assert(type(clustering.conf) == "table",
         "kong.clustering did not provide configuration")

  assert(type(clustering.cert) == "table",
         "kong.clustering did not provide the cluster certificate")

  assert(type(clustering.cert_key) == "cdata",
         "kong.clustering did not provide the cluster certificate private key")

  assert(kong.db.declarative_config,
         "kong.db.declarative_config was not initialized")

  local self = {
    declarative_config = kong.db.declarative_config,
    conf = clustering.conf,
    cert = clustering.cert,
    cert_key = clustering.cert_key,

    -- in konnect_mode, reconfigure errors will be reported to the control plane
    -- via WebSocket message
    error_reporting = clustering.conf.konnect_mode,
  }

  return setmetatable(self, _MT)
end


function _M:init_worker(basic_info)
  -- ROLE = "data_plane"

  self.plugins_list = basic_info.plugins
  self.filters = basic_info.filters

  -- only run in process which worker_id() == 0
  assert(ngx.timer.at(0, function(premature)
    self:communicate(premature)
  end))
end


local function send_ping(c, log_suffix)
  log_suffix = log_suffix or ""

  local hash = declarative.get_current_hash()

  if hash == "" or type(hash) ~= "string" then
    hash = DECLARATIVE_EMPTY_CONFIG_HASH
  end

  local _, err = c:send_ping(hash)
  if err then
    ngx_log(is_timeout(err) and ngx_NOTICE or ngx_WARN, _log_prefix,
            "unable to send ping frame to control plane: ", err, log_suffix)

  else
    ngx_log(ngx_DEBUG, _log_prefix, "sent ping frame to control plane", log_suffix)
  end
end


---@param c resty.websocket.client
---@param err_t kong.clustering.config_helper.update.err_t
---@param log_suffix? string
local function send_error(c, err_t, log_suffix)
  local payload, json_err = cjson_encode({
    type = "error",
    error = err_t,
  })

  if json_err then
    json_err = tostring(json_err)
    ngx_log(ngx_ERR, _log_prefix, "failed to JSON-encode error payload for ",
            "control plane: ", json_err, ", payload: ", inspect(err_t), log_suffix)

    payload = assert(cjson_encode({
      type = "error",
      error = {
        name = constants.CLUSTERING_DATA_PLANE_ERROR.GENERIC,
        message = "failed to encode JSON error payload: " .. json_err,
        source = "kong.clustering.data_plane.send_error",
        config_hash = err_t and err_t.config_hash
                      or DECLARATIVE_EMPTY_CONFIG_HASH,
      }
    }))
  end

  local ok, err = c:send_binary(payload)
  if not ok then
    ngx_log(ngx_ERR, _log_prefix, "failed to send error report to control plane: ",
            err, log_suffix)
  end
end


function _M:communicate(premature)
  if premature then
    -- worker wants to exit
    return
  end

  local conf = self.conf

  local log_suffix = " [" .. conf.cluster_control_plane .. "]"
  local reconnection_delay = math.random(5, 10)

  local c, uri, err = clustering_utils.connect_cp(self, "/v1/outlet")
  if not c then
    ngx_log(ngx_ERR, _log_prefix, "connection to control plane ", uri, " broken: ", err,
                 " (retrying after ", reconnection_delay, " seconds)", log_suffix)

    assert(ngx.timer.at(reconnection_delay, function(premature)
      self:communicate(premature)
    end))
    return
  end

  local labels do
    if kong.configuration.cluster_dp_labels then
      labels = {}
      for _, lab in ipairs(kong.configuration.cluster_dp_labels) do
        local del = lab:find(":", 1, true)
        labels[lab:sub(1, del - 1)] = lab:sub(del + 1)
      end
    end
  end

  local configuration = kong.configuration.remove_sensitive()

  -- connection established
  -- first, send out the plugin list and DP labels to CP
  -- The CP will make the decision on whether sync will be allowed
  -- based on the received information
  local _
  _, err = c:send_binary(cjson_encode({ type = "basic_info",
                                        plugins = self.plugins_list,
                                        process_conf = configuration,
                                        filters = self.filters,
                                        labels = labels, }))
  if err then
    ngx_log(ngx_ERR, _log_prefix, "unable to send basic information to control plane: ", uri,
                     " err: ", err, " (retrying after ", reconnection_delay, " seconds)", log_suffix)

    c:close()
    assert(ngx.timer.at(reconnection_delay, function(premature)
      self:communicate(premature)
    end))
    return
  end

  local config_semaphore = semaphore.new(0)

  -- how DP connection management works:
  -- three threads are spawned, when any of these threads exits,
  -- it means a fatal error has occurred on the connection,
  -- and the other threads are also killed
  --
  -- * config_thread: it grabs a received declarative config and apply it
  --                  locally. In addition, this thread also persists the
  --                  config onto the local file system
  -- * read_thread: it is the only thread that sends WS frames to the CP
  --                by sending out periodic PING frames to CP that checks
  --                for the healthiness of the WS connection. In addition,
  --                PING messages also contains the current config hash
  --                applied on the local Kong DP
  -- * write_thread: it is the only thread that receives WS frames from the CP,
  --                 and is also responsible for handling timeout detection

  local ping_immediately
  local config_exit
  local next_data
  local config_err_t

  local config_thread = ngx.thread.spawn(function()
    while not exiting() and not config_exit do
      local ok, err = config_semaphore:wait(1)

      if not ok then
        if err ~= "timeout" then
          ngx_log(ngx_ERR, _log_prefix, "semaphore wait error: ", err)
        end

        goto continue
      end

      local data = next_data
      if not data then
        goto continue
      end

      local msg = assert(inflate_gzip(data))
      yield()
      msg = assert(cjson_decode(msg))
      yield()

      if msg.type ~= "reconfigure" then
        goto continue
      end

      ngx_log(ngx_DEBUG, _log_prefix, "received reconfigure frame from control plane",
                         msg.timestamp and " with timestamp: " .. msg.timestamp or "",
                         log_suffix)

      local err_t
      ok, err, err_t = config_helper.update(self.declarative_config, msg)

      if ok then
        ping_immediately = true

      else
        if self.error_reporting then
          config_err_t = err_t
        end
        ngx_log(ngx_ERR, _log_prefix, "unable to update running config: ", err)
      end

      if next_data == data then
        next_data = nil
      end

      ::continue::
    end
  end)

  local write_thread = ngx.thread.spawn(function()
    local counter = 0   -- count down to ping

    while not exiting() do
      if ping_immediately or counter <= 0 then
        ping_immediately = nil
        counter = PING_INTERVAL

        send_ping(c, log_suffix)
      end

      if config_err_t then
        local err_t = config_err_t
        config_err_t = nil
        send_error(c, err_t, log_suffix)
      end

      counter = counter - 1

      ngx_sleep(1)
    end
  end)

  local read_thread = ngx.thread.spawn(function()
    local last_seen = ngx_time()

    while not exiting() do
      local data, typ, err = c:recv_frame()
      if err then
        if not is_timeout(err) then
          return nil, "error while receiving frame from control plane: " .. err
        end

        local waited = ngx_time() - last_seen
        if waited > PING_WAIT then
          return nil, "did not receive pong frame from control plane within " .. PING_WAIT .. " seconds"
        end

        goto continue
      end

      if typ == "close" then
        ngx_log(ngx_DEBUG, _log_prefix, "received close frame from control plane", log_suffix)
        return nil
      end

      last_seen = ngx_time()

      if typ == "binary" then
        next_data = data
        if config_semaphore:count() <= 0 then
          -- the following line always executes immediately after the `if` check
          -- because `:count` will never yield, end result is that the semaphore
          -- count is guaranteed to not exceed 1
          config_semaphore:post()
        end

        goto continue
      end

      if typ == "pong" then
        ngx_log(ngx_DEBUG, _log_prefix,
                "received pong frame from control plane",
                log_suffix)

        goto continue
      end

      -- unknown websocket frame
      ngx_log(ngx_NOTICE, _log_prefix,
              "received unknown (", tostring(typ), ") frame from control plane",
              log_suffix)

      ::continue::
    end
  end)

  local ok, err, perr = ngx.thread.wait(read_thread, write_thread, config_thread)

  ngx.thread.kill(read_thread)
  ngx.thread.kill(write_thread)
  c:close()

  local err_msg = ok and err or perr

  if err_msg and endswith(err_msg, ": closed") then
    ngx_log(ngx_INFO, _log_prefix, "connection to control plane closed", log_suffix)

  elseif err_msg then
    ngx_log(ngx_ERR, _log_prefix, err_msg, log_suffix)
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
