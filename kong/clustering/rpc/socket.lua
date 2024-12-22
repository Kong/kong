-- socket represents an open WebSocket connection
-- unlike the WebSocket object, it can be accessed via different requests
-- with the help of semaphores


local _M = {}
local _MT = { __index = _M, }


local utils = require("kong.clustering.rpc.utils")
local queue = require("kong.clustering.rpc.queue")
local jsonrpc = require("kong.clustering.rpc.json_rpc_v2")
local constants = require("kong.constants")
local isarray = require("table.isarray")


local assert = assert
local unpack = unpack
local string_format = string.format
local kong = kong
local is_timeout = utils.is_timeout
local compress_payload = utils.compress_payload
local decompress_payload = utils.decompress_payload
local exiting = ngx.worker.exiting
local ngx_time = ngx.time
local ngx_log = ngx.log
local new_error = jsonrpc.new_error


local CLUSTERING_PING_INTERVAL = constants.CLUSTERING_PING_INTERVAL
local PING_WAIT = CLUSTERING_PING_INTERVAL * 1.5
local PING_TYPE = "PING"
local PONG_TYPE = "PONG"
local ngx_WARN = ngx.WARN
local ngx_DEBUG = ngx.DEBUG


-- create a new socket wrapper, wb is the WebSocket object to use
-- timeout and max_payload_len must already been set by caller when
-- creating the `wb` object
function _M.new(manager, wb, node_id)
  local self = {
    wb = wb,
    interest = {}, -- id: callback pair
    outgoing = queue.new(4096), -- write queue
    manager = manager,
    node_id = node_id,
    sequence = 0,
  }

  return setmetatable(self, _MT)
end


function _M:_get_next_id()
  local res = self.sequence
  self.sequence = res + 1

  return res
end


function _M:push_request(msg)
  return self.outgoing:push(msg)
end


function _M:push_result(msg, err_prefix, results)
  -- may be a batch
  if results then
    table.insert(results, msg)
    return true
  end

  local res, err = self.outgoing:push(msg)
  if not res then
    return nil, err_prefix .. err
  end

  return true
end


function _M._dispatch(premature, self, cb, payload, results)
  if premature then
    return
  end

  local res, err = cb(self.node_id, unpack(payload.params))
  if not res then
    ngx_log(ngx_WARN, "[rpc] RPC callback failed: ", err)

    -- notification has no response
    if not payload.id then
      return
    end

    res, err = self:push_result(new_error(payload.id, jsonrpc.SERVER_ERROR, err),
                                "[rpc] unable to push RPC call error: ",
                                results)
    if not res then
      ngx_log(ngx_WARN, err)
    end

    return
  end

  -- notification has no response
  if not payload.id then
    ngx_log(ngx_DEBUG, "[rpc] notification has no response")
    return
  end

  -- success
  res, err = self:push_result({
    jsonrpc = jsonrpc.VERSION,
    id = payload.id,
    result = res,
  }, "[rpc] unable to push RPC call result: ", results)
  if not res then
    ngx_log(ngx_WARN, err)
  end
end


function _M:process_rpc_msg(payload, results)
  assert(payload.jsonrpc == jsonrpc.VERSION)

  local payload_id = payload.id

  if payload.method then
    -- invoke

    ngx_log(ngx_DEBUG, "[rpc] got RPC call: ", payload.method, " (id: ", payload_id, ")")

    local dispatch_cb = self.manager.callbacks.callbacks[payload.method]
    if not dispatch_cb and payload_id then
      local res, err = self:push_result(new_error(payload_id, jsonrpc.METHOD_NOT_FOUND),
                                        "unable to send \"METHOD_NOT_FOUND\" error back to client: ",
                                        results)
      if not res then
        return nil, err
      end

      return true
    end

    -- call dispatch
    local res, err = kong.timer:named_at(string_format("JSON-RPC callback for node_id: %s, id: %d, method: %s",
                                                       self.node_id, payload_id or 0, payload.method),
                                         0, _M._dispatch, self, dispatch_cb, payload, results)
    if not res and payload_id then
      local reso, erro = self:push_result(new_error(payload_id, jsonrpc.INTERNAL_ERROR),
                                          "unable to send \"INTERNAL_ERROR\" error back to client: ",
                                          results)
      if not reso then
        return nil, erro
      end

      return nil, "unable to dispatch JSON-RPC callback: " .. err
    end

  else
    -- response
    local interest_cb = self.interest[payload_id]
    self.interest[payload_id] = nil -- edge trigger only once

    if not interest_cb then
      ngx_log(ngx_WARN, "[rpc] no interest for RPC response id: ", payload_id, ", dropping it")

      return true
    end

    local res, err = interest_cb(payload)
    if not res then
      ngx_log(ngx_WARN, "[rpc] RPC response interest handler failed: id: ",
              payload_id, ", err: ", err)
    end
  end -- if payload.method

  return true
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

        if waited > CLUSTERING_PING_INTERVAL then
          local res, err = self:push_result(PING_TYPE, "unable to send ping: ")
          if not res then
            return nil, err
          end
        end

        -- timeout
        goto continue
      end

      last_seen = ngx_time()

      if typ == "ping" then
        local res, err = self:push_result(PONG_TYPE, "unable to handle ping: ")
        if not res then
          return nil, err
        end

        goto continue
      end

      if typ == "pong" then
        ngx_log(ngx_DEBUG, "[rpc] got PONG frame")

        goto continue
      end

      if typ == "close" then
        return true
      end

      assert(typ == "binary")

      local payload = decompress_payload(data)

      if not isarray(payload) then
        local ok, err = self:process_rpc_msg(v)
        if not ok then
          return nil, err
        end

        goto continue
      end

      -- rpc batching
      local results = {}

      for _, v in ipairs(payload) do
        local ok, err = self:process_rpc_msg(v, results)
        if not ok then
          return nil, err
        end
      end

      if #results == 0 then
        goto continue
      end

      local res, err = self.outgoing:push(results)
      if not res then
        return nil, "[rpc] unable to push RPC call result: " .. err
      end

      ::continue::
    end
  end)

  self.write_thread = ngx.thread.spawn(function()
    while not exiting() do
      local payload, err = self.outgoing:pop(5)
      if err then
        return nil, err
      end

      if payload then
        if payload == PING_TYPE then
          local _, err = self.wb:send_ping()
          if err then
            return nil, "failed to send PING frame to peer: " .. err

          else
            ngx_log(ngx_DEBUG, "[rpc] sent PING frame to peer")
          end

        elseif payload == PONG_TYPE then
          local _, err = self.wb:send_pong()
          if err then
            return nil, "failed to send PONG frame to peer: " .. err

          else
            ngx_log(ngx_DEBUG, "[rpc] sent PONG frame to peer")
          end

        else
          assert(type(payload) == "table")

          local bytes, err = self.wb:send_binary(compress_payload(payload))
          if not bytes then
            return nil, err
          end
        end
      end
    end
  end)
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

  if self.wb.close then
    self.wb:close()

  else
    self.wb:send_close()
  end
end


-- asynchronously start executing a RPC, _node_id is not
-- needed for this implementation, but it is important
-- for concentrator socket, so we include it just to keep
-- the signature consistent
function _M:call(node_id, method, params, callback)
  assert(node_id == self.node_id)

  local id

  -- notification has no callback or id
  if callback then
    id = self:_get_next_id()
    self.interest[id] = callback
  end

  return self:push_request({
    jsonrpc = jsonrpc.VERSION,
    method = method,
    params = params,
    id = id,
  })
end


return _M
