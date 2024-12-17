local kong_meta = require("kong.meta")

local _M = {
  PRIORITY = 1000,
  VERSION = kong_meta.version,
}

local original_callbacks = {}
local inc_id = 0

function _M.init_worker()
  kong.rpc.callbacks:register("kong.rpc.debug.register", function(node_id, register_payload)
    local proxy_apis = register_payload.proxy_apis

    for _, proxy_api in ipairs(proxy_apis) do
      -- unregister and save the original callback
      local original_cb
      if not original_callbacks[proxy_api] then
        original_callbacks[proxy_api] = kong.rpc.callbacks.callbacks[proxy_api]
      end
      original_cb = original_callbacks[proxy_api]
      kong.rpc.callbacks.callbacks[proxy_api] = nil

      kong.log.info("hooking registering RPC proxy API: ", proxy_api)
      kong.rpc.callbacks:register(proxy_api, function(client_id, payload)
        local id = inc_id
        inc_id = inc_id + 1
        kong.log.info("hooked proxy API ", proxy_api, " called by node: ", client_id)
        kong.log.info("forwarding to node: ", node_id)
        local res, err = kong.rpc:call(node_id, "kong.rpc.debug.mock", { call_id = id, method = proxy_api, node_id = client_id, payload = payload })
        if not res then
          return nil, "Failed to proxy(" .. node_id .. "): " .. err
        end

        if res.error then
          return nil, res.error
        end

        if res.prehook or res.posthook then
          if res.prehook then
            payload = res.args
          end

          local origin_res, origin_err = original_cb(client_id, payload)

          if res.posthook then
            res, err = kong.rpc:call(node_id, "kong.rpc.debug.posthook", { call_id = id, method = proxy_api, node_id = client_id, payload = {result = origin_res, error = origin_err} })
            if not res then
              return nil, "Failed to call post hook(" .. node_id .. "): " .. err
            end

            return res.result, res.error
          end
        elseif res.mock then
          return res.result, res.error
        end

        return nil, "invalid response from proxy"
      end)
    end

    return true
  end)

  kong.rpc.callbacks:register("kong.rpc.debug.call", function(node_id, payload)
    local res, err = kong.rpc:call(payload.node_id, payload.method, payload.args)
    return res, err
  end)

  kong.rpc.callbacks:register("kong.rpc.debug.lua_code", function(node_id, payload)
    local code = assert(loadstring(payload))
    return code()
  end)
end

return _M
