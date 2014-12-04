-- Copyright (C) Mashape, Inc.

require "LuaXML"

local cjson = require "cjson"
local inspect = require "inspect"

local _M = {}

function _M.execute()
  ngx.log(ngx.DEBUG, "Body Filter")

  if ngx.ctx.xml_to_json then

    local xml = xml.eval(ngx.arg[1])
    local json = cjson.encode(xml)

    ngx.arg[1] = json
    ngx.arg[2] = true
  end

end

return _M
