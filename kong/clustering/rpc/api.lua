local callbacks = require("kong.clustering.rpc.callbacks")


local spawn = ngx.thread.spawn
local wait  = ngx.thread.wait


local _M = {}
local _MT = { __index = _M, }


function _M.new(instance)
  local self = {
    instance = instance,
  }

  return setmetatable(self, _MT)
end


function _M:register(method, func)
  callbacks.register(method, func)
end


function _M:unregister(method)
  callbacks.unregister(method)
end


function _M:get_nodes()
  return self.instance:get_nodes()
end


function _M:invoke(func, id, ...)
  local instance = self.instance
  return instance[func](instance, id, ...)
end


function _M:invoke_multi(func, ...)
  local instance = self.instance
  local params = {...}

  -- node_id == "*"
  local idx = 1
  local threads = {}

  for id, count in pairs(self.nodes) do
    if count > 0 then
      threads[idx] = spawn(function()
        return self:invoke(func, id, unpack(params))
      end)
      idx = idx + 1
    end
  end

  local results = {}
  for i = 1, #threads do
    local ok, res = wait(threads[i])
    results[i] = ok and res or false
  end

  return results
end


function _M:notify(node_id, method, params, opts)
  if node_id ~= "*" then
    return self:invoke("notify", node_id, method, params, opts)
  end

  return self:invoke_multi("notify", method, params, opts)
end


function _M:call(node_id, method, params, opts)
  if node_id ~= "*" then
    return self:invoke("call", node_id, method, params, opts)
  end

  return self:invoke_multi("call", method, params, opts)
end


return _M
