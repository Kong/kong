local _M = {}


local semaphore = require("ngx.semaphore")
local msgpack = require("MessagePack")


local mp_pack = msgpack.pack
local mp_unpack = msgpack.unpack
local ngx_log = ngx.log
local exiting = ngx.worker.exiting
local table_remove = table.remove
local ngx_exit = ngx.exit


local ngx_WARN = ngx.WARN
local ngx_ERR = ngx.ERR
local ngx_OK = ngx.OK
local TOPIC_BASIC_INFO = "basic_info"


function _M.new(parent)
  local self = {
    clients = setmetatable({}, { __mode = "k", }),
    callbacks = {},
  }

  return setmetatable(self, {
    __index = function(tab, key)
      return _M[key] or parent[key]
    end,
  })
end


function _M:handle_cp_protocol()
  -- use mutual TLS authentication
  if self.conf.cluster_mtls == "shared" then
    self:validate_shared_cert()

  elseif self.conf.cluster_ocsp ~= "off" then
    local res, err = check_for_revocation_status()
    if res == false then
      ngx_log(ngx_ERR, "DP client certificate was revoked: ", err)
      return ngx_exit(444)

    elseif not res then
      ngx_log(ngx_WARN, "DP client certificate revocation check failed: ", err)
      if self.conf.cluster_ocsp == "on" then
        return ngx_exit(444)
      end
    end
  end

  local sock, err = ngx.req.socket(true)
  local queue
  do
    local queue_semaphore = semaphore.new()
    queue = {
      wait = function(...)
        return queue_semaphore:wait(...)
      end,
      post = function(...)
        return queue_semaphore:post(...)
      end
    }
  end

  local m = message.unpack_from_socket(sock)
  assert(m.topic == TOPIC_BASIC_INFO)
  local basic_info = mp_unpack(m.message)
  self.clients[basic_info.node_id] = queue

  local read_thread = ngx.thread.spawn(function()
    while not exiting() do
      local m = message.unpack_from_socket(sock)
      local callback = self.callbacks[m.topic]
      if callback then
        local succ, err = pcall(callback, m)
        if not succ then
          ngx_log(ngx_WARN, "callback for topic \"", m.topic,
                            "\" failed: ", err)
        end

      else
        ngx_log(ngx_WARN, "discarding incoming messages because callback "..
                          "for topic \"", m.topic, "\" doesn't exist")
      end
    end
  end)

  local write_thread = ngx.thread.spawn(function()
    while not exiting() do
      local ok, err = queue.wait(5)
      if ok then
        local message = table_remove(queue, 1)
        if not message then
          return nil, "send queue can not be empty after semaphore returns"
        end

        local res, err = sock:send(message:pack())
        if not res then
          return nil, "failed to send message: " .. err
        end

      elseif err ~= "timeout" then
        return nil, "semaphore wait error: " .. err
      end
    end
  end)

  local ok, err, perr = ngx.thread.wait(write_thread, read_thread)

  ngx.thread.kill(write_thread)
  ngx.thread.kill(read_thread)

  if not ok then
    ngx_log(ngx_ERR, err)
    return ngx_exit(ngx_ERR)
  end

  if perr then
    ngx_log(ngx_ERR, perr)
    return ngx_exit(ngx_ERR)
  end

  return ngx_exit(ngx_OK)
end


function _M:register_callback(topic, callback)
  assert(not self.callbacks[topic])

  self.callbacks[topic] = callback
end


function _M:init_worker()
  -- role = "control_plane"
end

return _M
