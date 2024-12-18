local rpc_mgr = require("kong.clustering.rpc.manager")

local _M = {
  PRIORITY = 1000,
  VERSION = kong_meta.version,
}

local original_callbacks = {}

function _M.init_worker()
  kong.rpc.callbacks:register("kong.rpc.proxy.register", function(node_id, register_payload)
    local proxy_apis = register_payload.proxy_apis

    for _, proxy_api in ipairs(proxy_apis) do
      kong.log.info("Hook registering RPC proxy API: ", proxy_api)
      local original = kong.rpc.callbacks[proxy_api]
      if original and not original_callbacks[proxy_api] then
        original_callbacks[proxy_api] = original
      end
      kong.rpc.callbacks[proxy_api] = nil
      kong.rpc.callbacks:register(proxy_api, function(client_id, payload)
        local res, err = kong.rpc:call(node_id, "kong.rpc.proxy", { method = proxy_api, node_id = client_id, payload = payload })
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

          local origin_res, origin_err = original(client_id, payload)

          if res.posthook then
            res, err = kong.rpc:call(node_id, "kong.rpc.proxy.posthook", { method = proxy_api, node_id = client_id, payload = {result = origin_res, error = origin_err} })
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
  end)
end
