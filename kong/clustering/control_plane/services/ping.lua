local callbacks = require("kong.clustering.rpc.callbacks")


local _M = {}
local _MT = { __index = _M, }


function _M.new()
  local self = {}

  return setmetatable(self, _MT)
end


function _M:init()
  callbacks.register("kong.test.v1.ping", function(params)
    ngx.log(ngx.ERR, "xxx ping received: ", params.msg)
    return { msg = "pong for " .. params.msg }
  end)

end


return _M
