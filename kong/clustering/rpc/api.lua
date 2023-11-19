local callbacks = require("kong.clustering.rpc.callbacks")


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


-- opts.node_id
function _M:notify(node_id, method, params, opts)
  return self.instance:notify(node_id, method, params, opts)
end


function _M:call(node_id, method, params, opts)
  return self.instance:call(node_id, method, params, opts)
end


return _M
