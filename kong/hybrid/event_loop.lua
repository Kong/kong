local _M = {}


local queue = require("kong.hybrid.queue")
local message = require("kong.hybrid.message")
local constants = require("kong.constants")


local exiting = ngx.worker.exiting
local pcall = pcall
local ngx_log = ngx.log
local ngx_time = ngx.time


local ngx_WARN = ngx.WARN
local ngx_DEBUG = ngx.DEBUG
local _MT = { __index = _M, }
local PING_INTERVAL = constants.CLUSTERING_PING_INTERVAL
local PING_WAIT = PING_INTERVAL * 1.5


function _M.new(node_id)
  local self = {
    callbacks = {},
    clients = {},
    node_id = assert(node_id),
  }

  self = setmetatable(self, _MT)

  self:register_callback("kong:hybrid:ping", function(m)
    local pong = message.new(node_id, m.src, "kong:hybrid:pong", "")
    self:send(pong)
    ngx_log(ngx_DEBUG, "sent pong to: ", m.src)
  end)

  self:register_callback("kong:hybrid:pong", function(m)
    ngx_log(ngx_DEBUG, "received pong from: ", m.src)
  end)

  return self
end


function _M:handle_peer(peer_id, sock)
  if self.clients[peer_id] then
    return nil, "duplicate client: " .. peer_id
  end

  local q = queue.new()
  self.clients[peer_id] = q

  local ping_thread = ngx.thread.spawn(function()
    while not exiting() do
      ngx.sleep(PING_INTERVAL)

      local m = message.new(self.node_id, peer_id, "kong:hybrid:ping", "")
      q:enqueue(m)
      ngx_log(ngx_DEBUG, "sent ping to: ", peer_id)
    end
  end)

  local read_thread = ngx.thread.spawn(function()
    local last_seen = ngx_time()

    while not exiting() do
      local m, err = message.unpack_from_socket(sock)
      if m then
        last_seen = ngx_time()

        local callback = self.callbacks[m.topic]
        if callback then
          local succ, err = pcall(callback, m)
          if not succ then
            ngx_log(ngx_WARN, "callback for topic \"", m.topic,
                              "\" failed: ", err)
          end

          m:release()

        else
          ngx_log(ngx_WARN, "discarding incoming messages because callback "..
                            "for topic \"", m.topic, "\" doesn't exist")
        end

      elseif err == "timeout" then
        local waited = ngx_time() - last_seen
        if waited > PING_WAIT then
          return nil, "did not receive PING frame from " .. peer_id ..
                      " within " .. PING_WAIT .. " seconds"
        end

      else
        return nil, "failed to receive message from DP: " .. err
      end
    end
  end)

  local write_thread = ngx.thread.spawn(function()
    while not exiting() do
      local message, err = q:dequeue()
      if message then
        local res, err = sock:send(message:pack())
        message:release()

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
  ngx.thread.kill(ping_thread)

  self.clients[peer_id] = nil

  if not ok then
    return nil, err
  end

  if perr then
    return nil, perr
  end

  return true
end


function _M:send(message)
  if not message.src then
    message.src = self.node_id
  end

  local q = self.clients[message.dest]
  if not q then
    return nil, "node " .. message.dest .. " is disconnected"
  end

  q:enqueue(message)

  return true
end


function _M:register_callback(topic, callback)
  assert(not self.callbacks[topic])

  self.callbacks[topic] = callback
end


return _M
