local _M = {}
local _MT = { __index = _M, }


local semaphore = require("ngx.semaphore")
local cjson = require("cjson.safe")
local constants = require("kong.constants")
local protocol = require("kong.clustering.protocol")
local config_helper = require("kong.clustering.config_helper")
local get_current_hash = require("kong.db.declarative").get_current_hash
local get_updated_monotonic_ms = require("kong.tools.utils").get_updated_monotonic_ms


local type = type
local pcall = pcall
local assert = assert
local setmetatable = setmetatable
local ipairs = ipairs
local math = math
local tostring = tostring
local sub = string.sub
local ngx = ngx
local cjson_decode = cjson.decode
local cjson_encode = cjson.encode
local exiting = ngx.worker.exiting


local PING_INTERVAL = constants.CLUSTERING_PING_INTERVAL
local PING_WAIT = PING_INTERVAL * 1.5
local LOG_PREFIX = "[clustering] "
local DECLARATIVE_EMPTY_CONFIG_HASH = constants.DECLARATIVE_EMPTY_CONFIG_HASH


local function is_timeout(err)
  return err and sub(err, -7) == "timeout"
end


function _M.new(clustering)
  assert(type(clustering) == "table", "kong.clustering is not instantiated")
  assert(type(clustering.conf) == "table", "kong.clustering did not provide configuration")
  assert(type(clustering.cert) == "table", "kong.clustering did not provide the cluster certificate")
  assert(type(clustering.cert_key) == "cdata", "kong.clustering did not provide the cluster certificate private key")

  local self = {
    declarative_config = kong.db.declarative_config,
    conf = clustering.conf,
    cert = clustering.cert,
    cert_key = clustering.cert_key,
  }

  return setmetatable(self, _MT)
end


function _M:init_worker(basic_info)
  -- ROLE = "data_plane"
  self.plugins_list = basic_info.plugins
  self.filters = basic_info.filters

  -- only run in process which worker_id() == 0 or privileged agent when that is turned on
  assert(ngx.timer.at(0, function(premature)
    self:communicate(premature)
  end))
end


local function send_ping(c, log_suffix)
  log_suffix = log_suffix or ""

  local hash = get_current_hash()
  if hash == "" or type(hash) ~= "string" then
    hash = DECLARATIVE_EMPTY_CONFIG_HASH
  end

  local _, err = c:send_ping(hash)
  if err then
    ngx.log(is_timeout(err) and ngx.NOTICE or ngx.WARN, LOG_PREFIX,
            "unable to send ping frame to control plane: ", err, log_suffix)

  else
    ngx.log(ngx.DEBUG, LOG_PREFIX, "sent ping frame to control plane", log_suffix)
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

  local wb, uri, err = require("kong.clustering.utils").connect_cp(self, "/v1/outlet")
  if not wb then
    ngx.log(ngx.ERR, LOG_PREFIX, "connection to control plane ", uri, " broken: ", err,
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
  _, err = wb:send_binary(cjson_encode({ type = "basic_info",
                                         plugins = self.plugins_list,
                                         process_conf = configuration,
                                         filters = self.filters,
                                         labels = labels, }))
  if err then
    ngx.log(ngx.ERR, LOG_PREFIX, "unable to send basic information to control plane: ", uri,
                     " err: ", err, " (retrying after ", reconnection_delay, " seconds)", log_suffix)

    wb:close()
    assert(ngx.timer.at(reconnection_delay, function(premature)
      self:communicate(premature)
    end))
    return
  end

  local config_semaphore = semaphore.new(0)

  -- How DP connection management works:
  --
  -- Three threads are spawned, when any of these threads exits,
  -- it means a fatal error has occurred on the connection,
  -- and the other threads are also killed.
  --
  -- * config_thread: it grabs a received declarative config and apply it
  --                  locally. In addition, this thread also persists the
  --                  config onto the local file system
  --
  -- * write_thread:  it is the only thread that receives WS frames from the CP,
  --                  and is also responsible for handling timeout detection
  --
  -- * read_thread:   it is the only thread that sends WS frames to the CP
  --                  by sending out periodic PING frames to CP that checks
  --                  for the healthiness of the WS connection. In addition,
  --                  PING messages also contains the current config hash
  --                  applied on the local Kong DP

  local ping_immediately
  local config_exit
  local next_data

  local config_thread = ngx.thread.spawn(function()
    while not (config_exit or exiting()) do
      local ok, err = config_semaphore:wait(1)

      if not ok then
        if err ~= "timeout" then
          ngx.log(ngx.ERR, LOG_PREFIX, "semaphore wait error: ", err)
          ngx.sleep(0)
        end

      else
        local data = next_data
        if data then
          ngx.log(ngx.DEBUG, LOG_PREFIX, "received reconfigure frame from control plane",
                             data.timestamp and " with timestamp: " .. data.timestamp or "",
                             log_suffix)

          local config = assert(data.config)
          local start = get_updated_monotonic_ms()
          local pok, res, err = pcall(config_helper.update, self.declarative_config,
                                      config, data.hashes.config, data.hashes)
          if pok then
            ngx.log(ngx.DEBUG, LOG_PREFIX, "importing configuration took: ",
                               get_updated_monotonic_ms() - start, " ms", log_suffix)
            ping_immediately = true
          end

          if not pok or not res then
            ngx.log(ngx.ERR, LOG_PREFIX, "unable to update running config: ",
                             (not pok and res) or err)
          end

          if next_data == data then
            next_data = nil
          end
        end

        ngx.sleep(0)
      end
    end
  end)

  local write_thread = ngx.thread.spawn(function()
    local counter = 0 -- count down to ping
    while not (config_exit or exiting()) do
      if ping_immediately or counter <= 0 then
        ping_immediately = nil
        counter = PING_INTERVAL

        send_ping(wb, log_suffix)
      end

      counter = counter - 1

      ngx.sleep(1)
    end
  end)

  local read_thread = ngx.thread.spawn(function()
    local receive_start
    local last_seen = ngx.time()
    while not (config_exit or exiting()) do
      local data, typ, err = wb:recv_frame()
      if err then
        if not is_timeout(err) then
          return nil, "error while receiving frame from control plane: " .. err
        end

        local waited = ngx.time() - last_seen
        if waited > PING_WAIT then
          return nil, "did not receive pong frame from control plane within " .. PING_WAIT .. " seconds"
        end

      else
        if typ == "close" then
          ngx.log(ngx.DEBUG, LOG_PREFIX, "received close frame from control plane", log_suffix)
          return
        end

        last_seen = ngx.time()

        if typ == "pong" then
          ngx.log(ngx.DEBUG, LOG_PREFIX, "received pong frame from control plane", log_suffix)

        elseif typ == "binary" then
          local msg = assert(cjson_decode(data))
          if msg.hash == get_current_hash() then
            if msg.type == "reconfigure:start" then
              ngx.log(ngx.DEBUG, LOG_PREFIX, "same config received from control plane, no need to reload", log_suffix)
            end

          elseif msg.type == "reconfigure:start" then
            receive_start = get_updated_monotonic_ms()
            protocol.reconfigure_start(msg)

          elseif msg.type == "entities" then
            protocol.process_entities(msg)

          elseif msg.type == "reconfigure:end" then
            ngx.log(ngx.DEBUG, LOG_PREFIX, "received updated configuration from control plane: ",
                               get_updated_monotonic_ms()  - receive_start, " ms", log_suffix)

            next_data = protocol.reconfigure_end(msg)

            if config_semaphore:count() <= 0 then
              -- the following line always executes immediately after the `if` check
              -- because `:count` will never yield, end result is that the semaphore
              -- count is guaranteed to not exceed 1
              config_semaphore:post()
            end

          else
            ngx.log(ngx.NOTICE, LOG_PREFIX, "received unknown (", tostring(msg.type), ") message from control plane", log_suffix)
          end

        else
          ngx.log(ngx.NOTICE, LOG_PREFIX, "received unknown (", tostring(typ), ") frame from control plane", log_suffix)
        end

        ngx.sleep(0)
      end
    end
  end)

  local ok, err, perr = ngx.thread.wait(read_thread, write_thread, config_thread)
  ngx.thread.kill(read_thread)
  ngx.thread.kill(write_thread)
  wb:close()

  local err_msg = ok and err or perr
  if err_msg then
    if err_msg:sub(-8) == ": closed" then
      ngx.log(ngx.INFO, LOG_PREFIX, "connection to control plane closed", log_suffix)
    else
      ngx.log(ngx.ERR, LOG_PREFIX, err_msg, log_suffix)
    end
  end

  -- the config thread might be holding a lock if it's in the middle of an
  -- update, so we need to give it a chance to terminate gracefully
  config_exit = true

  ok, err, perr = ngx.thread.wait(config_thread)
  if not ok then
    ngx.log(ngx.ERR, LOG_PREFIX, err, log_suffix)

  elseif perr then
    ngx.log(ngx.ERR, LOG_PREFIX, perr, log_suffix)
  end

  ngx.thread.kill(config_thread)

  if not exiting() then
    assert(ngx.timer.at(reconnection_delay, function(premature)
      self:communicate(premature)
    end))
  end
end


return _M
