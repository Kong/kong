local _M = {}
local _MT = { __index = _M, }


local semaphore = require("ngx.semaphore")
local cjson = require("cjson.safe")
local config_helper = require("kong.clustering.config_helper")
local clustering_utils = require("kong.clustering.utils")
local declarative = require("kong.db.declarative")
local constants = require("kong.constants")
local utils = require("kong.tools.utils")


local assert = assert
local setmetatable = setmetatable
local math = math
local pcall = pcall
local tostring = tostring
local sub = string.sub
local ngx = ngx
local ngx_log = ngx.log
local ngx_sleep = ngx.sleep
local cjson_decode = cjson.decode
local cjson_encode = cjson.encode
local exiting = ngx.worker.exiting
local ngx_time = ngx.time
local inflate_gzip = utils.inflate_gzip
local yield = utils.yield


local ngx_ERR = ngx.ERR
local ngx_DEBUG = ngx.DEBUG
local ngx_WARN = ngx.WARN
local ngx_NOTICE = ngx.NOTICE
local PING_INTERVAL = constants.CLUSTERING_PING_INTERVAL
local PING_WAIT = PING_INTERVAL * 1.5
local _log_prefix = "[clustering] "
local DECLARATIVE_EMPTY_CONFIG_HASH = constants.DECLARATIVE_EMPTY_CONFIG_HASH


local function is_timeout(err)
  return err and sub(err, -7) == "timeout"
end


function _M.new(conf, cert, cert_key)
  local self = {
    declarative_config = declarative.new_config(conf),
    conf = conf,
    cert = cert,
    cert_key = cert_key,
  }

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


local function send_ping(c, log_suffix)
  log_suffix = log_suffix or ""

  local hash = declarative.get_current_hash()

  if hash == true then
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


function _M:communicate(premature)
  if premature then
    -- worker wants to exit
    return
  end

  local conf = self.conf

  local log_suffix = " [" .. conf.cluster_control_plane .. "]"
  local reconnection_delay = math.random(5, 10)

  local c, uri, err = clustering_utils.connect_cp(
                        "/v1/outlet", conf, self.cert, self.cert_key)
  if not c then
    ngx_log(ngx_ERR, _log_prefix, "connection to control plane ", uri, " broken: ", err,
                 " (retrying after ", reconnection_delay, " seconds)", log_suffix)

    assert(ngx.timer.at(reconnection_delay, function(premature)
      self:communicate(premature)
    end))
    return
  end

  -- connection established
  -- first, send out the plugin list to CP so it can make decision on whether
  -- sync will be allowed later
  local _
  _, err = c:send_binary(cjson_encode({ type = "basic_info",
                                        plugins = self.plugins_list, }))
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

  local config_thread = ngx.thread.spawn(function()
    while not exiting() and not config_exit do
      local ok, err = config_semaphore:wait(1)
      if ok then
        local data = next_data
        if data then
          local msg = assert(inflate_gzip(data))
          yield()
          msg = assert(cjson_decode(msg))
          yield()

          if msg.type == "reconfigure" then
            if msg.timestamp then
              ngx_log(ngx_DEBUG, _log_prefix, "received reconfigure frame from control plane with timestamp: ",
                                 msg.timestamp, log_suffix)

            else
              ngx_log(ngx_DEBUG, _log_prefix, "received reconfigure frame from control plane", log_suffix)
            end

            local config_table = assert(msg.config_table)
            local pok, res
            pok, res, err = pcall(config_helper.update, self.declarative_config,
                                  config_table, msg.config_hash, msg.hashes)
            if pok then
              if not res then
                ngx_log(ngx_ERR, _log_prefix, "unable to update running config: ", err)
              end

              ping_immediately = true

            else
              ngx_log(ngx_ERR, _log_prefix, "unable to update running config: ", res)
            end

            if next_data == data then
              next_data = nil
            end
          end
        end

      elseif err ~= "timeout" then
        ngx_log(ngx_ERR, _log_prefix, "semaphore wait error: ", err)
      end
    end
  end)

  local write_thread = ngx.thread.spawn(function()
    while not exiting() do
      send_ping(c, log_suffix)

      for _ = 1, PING_INTERVAL do
        ngx_sleep(1)
        if exiting() then
          return
        end
        if ping_immediately then
          ping_immediately = nil
          break
        end
      end
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

      else
        if typ == "close" then
          ngx_log(ngx_DEBUG, _log_prefix, "received close frame from control plane", log_suffix)
          return
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

        elseif typ == "pong" then
          ngx_log(ngx_DEBUG, _log_prefix, "received pong frame from control plane", log_suffix)

        else
          ngx_log(ngx_NOTICE, _log_prefix, "received unknown (", tostring(typ), ") frame from control plane",
                              log_suffix)
        end
      end
    end
  end)

  local ok, err, perr = ngx.thread.wait(read_thread, write_thread, config_thread)

  ngx.thread.kill(read_thread)
  ngx.thread.kill(write_thread)
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
