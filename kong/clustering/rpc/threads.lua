local constants = require("kong.clustering.rpc.constants")


local setmetatable = setmetatable


local sleep = ngx.sleep
local spawn = ngx.thread.spawn
local kill = ngx.thread.kill
local wait = ngx.thread.wait
local exiting = ngx.worker.exiting
local ngx_time = ngx.time


local PING_INTERVAL = constants.PING_INTERVAL
local PING_WAIT     = constants.PING_WAIT


local _M = {}
local _MT = { __index = _M, }


local function is_timeout(err)
  return err and err:sub(-7) == "timeout"
end


function _M.new(wb, hdl)
  local self = {
    wb = wb,
    handler = hdl,
  }

  return setmetatable(self, _MT)
end


function _M:abort()
  self.handler = nil
end


function _M:aborting()
  return not self.handler or
         exiting()
end


function _M:run()
  local wb = self.wb
  local handler = self.handler

  -- send data to peer
  local write_thread = spawn(function()
    local last_send = ngx_time()

    while not self:aborting() do
      -- get a send json data
      local data, err = handler:pop_send()

      if err then
        if not is_timeout(err) then
          return nil, "pop send data error: " .. err
        end

        -- timeout

        if ngx_time() - last_send > PING_INTERVAL then

          -- ping peer to keepalive
          local _, err = wb:send_ping()
          if err then
            return nil, "websocket send_ping error: " .. err
          end

          --ngx.log(ngx.ERR, "websocket send ping")

          last_send = ngx_time()
        end

        goto continue
      end

      if self:aborting() then
        return
      end

      assert(data)

      local _, err = wb:send_binary(data)
      if err then
        return nil, "websocket send_binary error: " .. err
      end

      last_send = ngx_time()

      ::continue::
    end -- while not aborting
  end)  -- write_thread

  -- receive request/response from peer
  local read_thread = spawn(function()
    local last_recv = ngx_time()

    while not self:aborting() do
      local data, typ, err = wb:recv_frame()

      if self:aborting() then
        return
      end

      if err then
        if not is_timeout(err) then
          return nil, "websocket recv_frame error: " .. err
        end

        -- timeout

        if ngx_time() - last_recv > PING_WAIT then
          return nil, "websocket did not receive any data " ..
                      "within " ..  PING_WAIT .. " seconds"
        end

        goto continue
      end

      if not data then
        return nil, "did not receive data from peer"
      end

      -- receives some data
      last_recv = ngx_time()

      -- dispatch request or response
      if typ == "binary" then
        handler:push_recv(data)
        goto continue
      end

      -- ping
      if typ == "ping" then
        local _, err = wb:send_pong()
        if err then
          return nil, "websocket send_pong error: " .. err
        end

        --ngx.log(ngx.ERR, "websocket send pong")

        goto continue
      end

      if typ == "close" then
        return
      end

      -- ignore others
      ::continue::
    end -- while not aborting
  end)  -- read_thread

  -- invoke rpc call
  local task_thread = spawn(function()
    while not self:aborting() do
      -- check request and call rpc
      handler:invoke_callback()

      -- yield, not block other threads
      sleep(0)
    end -- while not aborting
  end)  -- task_thread

  local ok, err, perr = wait(write_thread, read_thread, task_thread)

  kill(write_thread)
  kill(read_thread)
  kill(task_thread)

  if not ok then
      ngx.log(ngx.ERR, "websocket connect failed: ", err)
  end

  if perr then
      ngx.log(ngx.ERR, "websocket connect failed: ", perr)
  end
end


return _M

