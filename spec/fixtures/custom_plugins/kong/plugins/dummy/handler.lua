-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local BasePlugin = require "kong.plugins.base_plugin"


local DummyHandler = BasePlugin:extend()


DummyHandler.PRIORITY = 1000


function DummyHandler:new()
  DummyHandler.super.new(self, "dummy")
end


function DummyHandler:access()
  DummyHandler.super.access(self)

  if ngx.req.get_uri_args()["send_error"] then
    return kong.response.exit(404, { message = "Not found" })
  end

  ngx.header["Dummy-Plugin-Access-Header"] = "dummy"
end


function DummyHandler:header_filter(conf)
  DummyHandler.super.header_filter(self)

  ngx.header["Dummy-Plugin"] = conf.resp_header_value

  if conf.resp_code then
    ngx.status = conf.resp_code
  end

  if conf.append_body then
    ngx.header["Content-Length"] = nil
  end
end


function DummyHandler:body_filter(conf)
  DummyHandler.super.body_filter(self)

  if conf.append_body and not ngx.arg[2] then
    ngx.arg[1] = string.sub(ngx.arg[1], 1, -2) .. conf.append_body
  end
end


return DummyHandler
