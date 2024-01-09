-- socket represents an open WebSocket connection
-- unlike the WebSocket object, it can be accessed via different requests
-- with the help of semaphores


local _M = {}
local _MT = { __index = _M, }


local cjson = require("cjson.safe")
local future = require("kong.clustering.rpc.future")
local utils = require("kong.clustering.rpc.utils")
local queue = require("kong.clustering.rpc.queue")


local assert = assert
local cjson_encode = cjson.encode
local cjson_decode = cjson.decode
local is_timeout = utils.is_timeout
local unpack = table.unpack
local exiting = ngx.worker.exiting
local ngx_time = ngx.time
local ngx_log = ngx.log


local JSONRPC_SERVER_ERROR = -32000
local JSONRPC_UNKNOWN_METHOD = -32601
local PING_WAIT = constants.CLUSTERING_PING_INTERVAL * 1.5
local PONG_TYPE = "PONG"
local ngx_WARN = ngx.WARN
local ngx_DEBUG = ngx.DEBUG


-- create a new socket wrapper, wb is the WebSocket object to use
-- timeout and max_payload_len must already been set by caller when
-- creating the `wb` object
function _M.new(wb, node_id)
  local self = {
    wb = wb,
    interest = {}, -- id: callback pair
    outgoing = queue.new(4096), -- write queue
    incoming = queue.new(4096), -- new call queue
    node_id = node_id,
    sequence = 0,
  }

  return setmetatable(self, _MT)
end


function _M:get_next_id()
  local res = sequence
  self.sequence = res + 1

  return res
end


-- start reader and writer thread and event loop
function _M:start()
  self.read_thread = ngx.thread.spawn(function()
    local last_seen = ngx_time()

    while not exiting() do
      local data, typ, err = self.wb:recv_frame()

      if err then
        if not is_timeout(err) then
          return nil, err
        end

        local waited = ngx_time() - last_seen
        if waited > PING_WAIT then
          return nil, "did not receive ping frame from other end within " ..
                      PING_WAIT .. " seconds"
        end

        -- timeout
        goto continue
      end

      last_seen = ngx_time()

      if typ == "ping" then
        local res, err = self.outgoing:push(PONG_TYPE)
        if not res then
          return nil, "unable to handle ping: " .. err
        end

        goto continue
      end

      assert(typ == "binary")

      local payload = cjson_decode(data)
      assert(payload.jsonrpc == "2.0")

      if payload.method then
        -- invoke
        local res, err = self.incoming:push(payload)
        if not res then
          return nil, "unable to incoming RPC call: " .. err
        end

      else
        -- response
        local cb = self.interest[payload.id]
        self.interest[payload.id] = nil -- edge trigger only once

        if not cb then
          ngx_log(ngx_WARN, "[rpc] no interest for RPC response id: ", payload.id, ", dropping it")
        end

        local res, err = cb(payload)
        if not res then
          ngx_log(ngx_WARN, "[rpc] RPC response interest handler failed: id: ",
                  payload.id, ", err: ", err)
        end
      end

      ::continue::
    end
  end)

  self.write_thread = ngx.thread.spawn(function()
    while not exiting() do
      local payload, err = self.outgoing.pop(5)
      if err then
        return nil, err
      end

      if payload then
        if payload == PONG_TYPE then
          local _, err = self.wb:send_pong()
          if err then
            if not is_timeout(err) then
              return nil, "failed to send pong frame to data plane: " .. err
            end

            ngx_log(ngx_WARN, "[rpc] failed to send PONG frame to peer: ", err)

          else
            ngx_log(ngx_DEBUG, "[rpc] sent PONG frame to peer")
          end

          -- pong ok
          goto continue
        end

        local bytes, err = self.wb:send_binary(cjson_encode(payload))
        if not bytes then
          return nil, err
        end
      end

      ::continue::
    end
  end)

  return true
end


function _M:join()
  local ok, err, perr = ngx.thread.wait(self.write_thread, self.read_thread)
  self:stop()

  if not ok then
    return nil, err
  end

  if perr then
    return nil, perr
  end

  return true
end


function _M:stop()
  ngx.thread.kill(self.write_thread)
  ngx.thread.kill(self.read_thread)
  self.wb:send_close()
end


return _M
