local _M = {}


local queue = require("kong.hybrid.queue")
local message = require("kong.hybrid.message")


local exiting = ngx.worker.exiting()
local pcall = pcall
local ngx_log = ngx.log


local ngx_WARN = ngx.WARN


function _M.new(node_id)
  local self = {
    callbacks = {},
    clients = {},
    node_id = node_id,
  }

  return self
end


function _M:handle_peer(node_id, sock)
  if self.clients[node_id] then
    return nil, "duplicate client: " .. node_id
  end

  local q = queue.new()
  self.clients[node_id] = q

  local read_thread = ngx.thread.spawn(function()
    while not exiting() do
      local m, err = message.unpack_from_socket(sock)
      if m then
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

      elseif err ~= "timeout" then
        return nil, "failed to receive message from DP: " .. err
      end
    end
  end)

  local write_thread = ngx.thread.spawn(function()
    while not exiting() do
      local message, err = queue.dequeue()
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

  q.enqueue(message)

  return true
end


function _M:register_callback(topic, callback)
  assert(not self.callbacks[topic])

  self.callbacks[topic] = callback
end


return _M
