local _M = {}


local semaphore = require("ngx.semaphore")
local ws_client = require("resty.websocket.client")
local cjson = require("cjson.safe")
local declarative = require("kong.db.declarative")
local constants = require("kong.constants")
local utils = require("kong.tools.utils")
local system_constants = require("lua_system_constants")
local ffi = require("ffi")
local assert = assert
local setmetatable = setmetatable
local type = type
local math = math
local pcall = pcall
local tostring = tostring
local sub = string.sub
local ngx = ngx
local ngx_log = ngx.log
local ngx_sleep = ngx.sleep
local cjson_decode = cjson.decode
local cjson_encode = cjson.encode
local kong = kong
local exiting = ngx.worker.exiting
local ngx_time = ngx.time
local io_open = io.open
local inflate_gzip = utils.inflate_gzip
local deflate_gzip = utils.deflate_gzip


local KONG_VERSION = kong.version
local CONFIG_CACHE = ngx.config.prefix() .. "/config.cache.json.gz"
local ngx_ERR = ngx.ERR
local ngx_DEBUG = ngx.DEBUG
local ngx_INFO = ngx.INFO
local ngx_WARN = ngx.WARN
local ngx_NOTICE = ngx.NOTICE
local MAX_PAYLOAD = kong.configuration.cluster_max_payload
local WS_OPTS = {
  timeout = constants.CLUSTERING_TIMEOUT,
  max_payload_len = MAX_PAYLOAD,
}
local PING_INTERVAL = constants.CLUSTERING_PING_INTERVAL
local PING_WAIT = PING_INTERVAL * 1.5
local _log_prefix = "[clustering] "
local DECLARATIVE_EMPTY_CONFIG_HASH = constants.DECLARATIVE_EMPTY_CONFIG_HASH


local function is_timeout(err)
  return err and sub(err, -7) == "timeout"
end


function _M.new(parent)
  local self = {
    declarative_config = declarative.new_config(parent.conf),
  }

  return setmetatable(self, {
    __index = function(tab, key)
      return _M[key] or parent[key]
    end,
  })
end


function _M:encode_config(config)
  return deflate_gzip(config)
end


function _M:decode_config(config)
  return inflate_gzip(config)
end


function _M:update_config(config_table, config_hash, update_cache, hashes)
  assert(type(config_table) == "table")

  if not config_hash then
    config_hash, hashes = self:calculate_config_hash(config_table)
  end

  local current_hash = declarative.get_current_hash()
  if current_hash == config_hash then
    ngx_log(ngx_DEBUG, _log_prefix, "same config received from control plane, ",
                                    "no need to reload")
    return true
  end

  local entities, err, _, meta, new_hash =
    self.declarative_config:parse_table(config_table, config_hash)
  if not entities then
    return nil, "bad config received from control plane " .. err
  end

  if current_hash == new_hash then
    ngx_log(ngx_DEBUG, _log_prefix, "same config received from control plane, ",
                                    "no need to reload")
    return true
  end

  -- NOTE: no worker mutex needed as this code can only be
  -- executed by worker 0

  local res, err =
    declarative.load_into_cache_with_events(entities, meta, new_hash, hashes)
  if not res then
    return nil, err
  end

  if update_cache then
    -- local persistence only after load finishes without error
    local f, err = io_open(CONFIG_CACHE, "w")
    if not f then
      ngx_log(ngx_ERR, _log_prefix, "unable to open config cache file: ", err)

    else
      local config = assert(cjson_encode(config_table))
      config = assert(self:encode_config(config))
      res, err = f:write(config)
      if not res then
        ngx_log(ngx_ERR, _log_prefix, "unable to write config cache file: ", err)
      end

      f:close()
    end
  end

  return true
end


function _M:init_worker()
  -- ROLE = "data_plane"

  if ngx.worker.id() == 0 then
    local f = io_open(CONFIG_CACHE, "r")
    if f then
      local config, err = f:read("*a")
      if not config then
        ngx_log(ngx_ERR, _log_prefix, "unable to read cached config file: ", err)
      end

      f:close()

      if config and #config > 0 then
        ngx_log(ngx_INFO, _log_prefix, "found cached config, loading...")
        config, err = self:decode_config(config)
        if config then
          config, err = cjson_decode(config)
          if config then
            local res
            res, err = self:update_config(config)
            if not res then
              ngx_log(ngx_ERR, _log_prefix, "unable to update running config from cache: ", err)
            end

          else
            ngx_log(ngx_ERR, _log_prefix, "unable to json decode cached config: ", err, ", ignoring")
          end

        else
          ngx_log(ngx_ERR, _log_prefix, "unable to decode cached config: ", err, ", ignoring")
        end
      end

    else
      -- CONFIG_CACHE does not exist, pre create one with 0600 permission
      local flags = bit.bor(system_constants.O_RDONLY(),
                            system_constants.O_CREAT())

      local mode = ffi.new("int", bit.bor(system_constants.S_IRUSR(),
                                          system_constants.S_IWUSR()))

      local fd = ffi.C.open(CONFIG_CACHE, flags, mode)
      if fd == -1 then
        ngx_log(ngx_ERR, _log_prefix, "unable to pre-create cached config file: ",
                ffi.string(ffi.C.strerror(ffi.errno())))

      else
        ffi.C.close(fd)
      end
    end

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

  -- TODO: pick one random CP
  local address = conf.cluster_control_plane
  local log_suffix = " [" .. address .. "]"

  local c = assert(ws_client:new(WS_OPTS))
  local uri = "wss://" .. address .. "/v1/outlet?node_id=" ..
              kong.node.get_id() ..
              "&node_hostname=" .. kong.node.get_hostname() ..
              "&node_version=" .. KONG_VERSION

  local opts = {
    ssl_verify = true,
    client_cert = self.cert,
    client_priv_key = self.cert_key,
  }
  if conf.cluster_mtls == "shared" then
    opts.server_name = "kong_clustering"
  else
    -- server_name will be set to the host if it is not explicitly defined here
    if conf.cluster_server_name ~= "" then
      opts.server_name = conf.cluster_server_name
    end
  end

  local reconnection_delay = math.random(5, 10)
  local res, err = c:connect(uri, opts)
  if not res then
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

  local config_thread = ngx.thread.spawn(function()
    while not exiting() and not config_exit do
      local ok, err = config_semaphore:wait(1)
      if ok then
        local config_table = self.next_config
        if config_table then
          local config_hash  = self.next_hash
          local hashes = self.next_hashes

          local pok, res
          pok, res, err = pcall(self.update_config, self, config_table, config_hash, true, hashes)
          if pok then
            if not res then
              ngx_log(ngx_ERR, _log_prefix, "unable to update running config: ", err)
            end

            ping_immediately = true

          else
            ngx_log(ngx_ERR, _log_prefix, "unable to update running config: ", res)
          end

          if self.next_config == config_table then
            self.next_config = nil
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
          data = assert(inflate_gzip(data))

          local msg = assert(cjson_decode(data))

          if msg.type == "reconfigure" then
            if msg.timestamp then
              ngx_log(ngx_DEBUG, _log_prefix, "received reconfigure frame from control plane with timestamp: ",
                                 msg.timestamp, log_suffix)

            else
              ngx_log(ngx_DEBUG, _log_prefix, "received reconfigure frame from control plane", log_suffix)
            end

            self.next_config = assert(msg.config_table)
            self.next_hash = msg.config_hash
            self.next_hashes = msg.hashes

            if config_semaphore:count() <= 0 then
              -- the following line always executes immediately after the `if` check
              -- because `:count` will never yield, end result is that the semaphore
              -- count is guaranteed to not exceed 1
              config_semaphore:post()
            end
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
