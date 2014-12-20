-- Copyright (C) Mashape, Inc.

local cjson = require "cjson"
require "LuaXML"

local _M = {}

function _M.execute(conf)
  if ngx.ctx.xml_to_json then
    local xml = xml.eval(ngx.arg[1])
    local json = cjson.encode(xml)
    ngx.arg[1] = json
    ngx.arg[2] = true
  end
end

return _M
