local cjson = require "cjson"
local BasePlugin = require "kong.plugins.base_plugin"


local _M = BasePlugin:extend()


function _M:new()
  _M.super.new(self, "headers-inspect")
end


function _M.access()
  local headers = ngx.req.get_headers()
  local json = cjson.encode(headers)

  ngx.status = 200
  ngx.say(json)
  ngx.exit(200)
end


return _M
