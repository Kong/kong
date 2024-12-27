--- This plugin serves as a bridge for debugging RPC calls, allowing to incercept and manipulate the calls
-- debugging is supported by a set of RPC calls,
-- CP side:
-- 1. kong.rpc.debug.register: registers self as the debugger of the CP
--    params: nil
--    returns: true
-- 2. kong.rpc.debug.call: let CP to call a method on a node
--    returns: { result = "result", error = "error" }
--    params: { node_id = "node_id", method = "method", args = { ... } }
-- 3. kong.rpc.debug.lua_code: let CP to execute lua code on a node
--    params: "lua code"
--    returns: the return value of the lua code
--
--- debugger side:
-- 1. kong.rpc.debug.call_handler: the debugger will receive a call from the CP when a hooked API is called
--    params: { call_seq = "call_seq", method = "method", node_id = "node_id", payload = { ... } }
--    the debugger can return 2 types of responses:
--    a. { mock = true, result = "result", error = "error" }, if the API is mocked
--    b. { prehook = true/false, posthook = true/false, args = { ... }/nil }, boolean to be true if a prehook/posthook is present, and args to be the manipulated args
-- 2. kong.rpc.debug.call_handler_post: the debugger will receive a call from the CP when a posthook is called
--    params: { call_seq = "call_seq", method = "method", node_id = "node_id", payload = { result = "result", error = "error" } }
--    return: { result = "result", error = "error" }

local kong_meta = require("kong.meta")
local shallow_copy = require("kong.tools.table").shallow_copy
local debugger_prefix = "kong.rpc.debug."

local _M = {
  PRIORITY = 1000,
  VERSION = kong_meta.version,
}


local function hook(debugger_node_id)
  local original_callbacks = shallow_copy(kong.rpc.callbacks.callbacks)
  local next_call_seq = 0
  for api, cb in pairs(original_callbacks) do
    if api:sub(1, #debugger_prefix) == "kong.rpc.debug." then
      goto skip
    end

    kong.log.info("hooking registering RPC proxy API: ", api)
    -- re-register
    kong.rpc.callbacks.callbacks[api] = nil
    kong.rpc.callbacks:register(api, function(node_id, payload)
      local call_seq = next_call_seq
      next_call_seq = next_call_seq + 1
      kong.log.info("hooked proxy API ", api, " called by node: ", node_id)
      kong.log.info("forwarding to node: ", node_id)
      local res, err = kong.rpc:call(debugger_node_id, "kong.rpc.debug.call_handler", { call_seq = call_seq, method = api, node_id = node_id, payload = payload })
      if not res then
        return nil, "Failed to call debugger(" .. debugger_node_id .. "): " .. err
      end

      if res.error then
        return nil, res.error
      end

      -- no prehook/posthook, directly return mock result
      if res.mock then
        return res.result, res.error
      end

      if res.prehook then
        payload = res.args
      end

      local call_res, call_err = cb(node_id, payload)

      if res.posthook then
        res, err = kong.rpc:call(debugger_node_id, "kong.rpc.debug.call_handler_post",
          { call_seq = call_seq, method = api, node_id = node_id, payload = { result = call_res, error = call_err } })
        if not res then
          return nil, "Failed to call debugger post hook(" .. debugger_node_id .. "): " .. err
        end

        call_res, call_err = res.result, res.error
      end

      return call_res, call_err
    end)

    ::skip::
  end
end



function _M.init_worker()
  local registered
  kong.rpc.callbacks:register("kong.rpc.debug.register", function(node_id, register_payload)
    if registered then
      return nil, "already registered: " .. registered

    else
      registered = node_id
    end

    hook(node_id)

    return true
  end)

  kong.rpc.callbacks:register("kong.rpc.debug.call", function(node_id, payload)
    if node_id ~= registered then
      return nil, "not authorized"
    end

    local res, err = kong.rpc:call(payload.node_id, payload.method, payload.args)
    return {
      result = res,
      error = err,
    }
  end)

  kong.rpc.callbacks:register("kong.rpc.debug.lua_code", function(node_id, payload)
    if node_id ~= registered then
      return nil, "not authorized"
    end

    local code = assert(loadstring(payload))
    return code()
  end)
end

return _M
