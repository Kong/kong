local _M = {}
local _MT = { __index = _M, }


local cjson = require("cjson.safe")
local config_helper = require("kong.clustering.config_helper")
local clustering_utils = require("kong.clustering.utils")
local events = require("kong.clustering.events")
local declarative = require("kong.db.declarative")
local constants = require("kong.constants")
local utils = require("kong.tools.utils")
local pl_stringx = require("pl.stringx")


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
  }

  return setmetatable(self, _MT)
end


function _M:init_worker(plugins_list)
  -- ROLE = "data_plane"

  self.plugins_list = plugins_list

  -- only run in process which worker_id() == 0
  assert(ngx.timer.at(0, function(premature)
    self:communicate(premature)
  end))
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

  -- connection established
  -- first, send out the plugin list and DP labels to CP
  -- The CP will make the decision on whether sync will be allowed
  -- based no the received information
  local _
  _, err = c:send_binary(cjson_encode({ type = "basic_info",
                                        plugins = self.plugins_list,
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
  local next_data

  events.clustering_recv_config(function(data)
    if exiting() or not data then
      return
    end

    local msg = assert(inflate_gzip(data))
    yield()
    msg = assert(cjson_decode(msg))
    yield()

    if msg.type ~= "reconfigure" then
      return
    end

    ngx_log(ngx_DEBUG, _log_prefix, "received reconfigure frame from control plane",
                       msg.timestamp and " with timestamp: " .. msg.timestamp or "",
                       log_suffix)

    local config_table = assert(msg.config_table)

    local pok, res, err = pcall(config_helper.update, self.declarative_config,
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
          events.clustering_notify_recv_config(data)

        elseif typ == "pong" then
          ngx_log(ngx_DEBUG, _log_prefix, "received pong frame from control plane", log_suffix)

        else
          ngx_log(ngx_NOTICE, _log_prefix, "received unknown (", tostring(typ), ") frame from control plane",
                              log_suffix)
        end
      end
    end
  end)

  local ok, err, perr = ngx.thread.wait(read_thread, write_thread)

  ngx.thread.kill(read_thread)
  ngx.thread.kill(write_thread)
  c:close()

  local err_msg = ok and err or perr

  if err_msg and endswith(err_msg, ": closed") then
    ngx_log(ngx_INFO, _log_prefix, "connection to control plane closed", log_suffix)

  elseif err_msg then
    ngx_log(ngx_ERR, _log_prefix, err_msg, log_suffix)
  end

  if not exiting() then
    assert(ngx.timer.at(reconnection_delay, function(premature)
      self:communicate(premature)
    end))
  end
end

return _M
