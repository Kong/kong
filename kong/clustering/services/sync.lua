local callbacks = require("kong.clustering.rpc.callbacks")


local _M = {}
local _MT = { __index = _M, }


function _M.new()
  local self = {}

  return setmetatable(self, _MT)
end


function _M:init()
  callbacks.register("kong.sync.v1.push_all", function(params)
    ngx.log(ngx.ERR, "xxx sync push all, data len=", #params.data)
    return { msg = "sync ok " }
  end)

end


return _M
