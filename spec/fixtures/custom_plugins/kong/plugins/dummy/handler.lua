local BasePlugin = require "kong.plugins.base_plugin"


local DummyHandler = BasePlugin:extend()


DummyHandler.PRIORITY = 1000


function DummyHandler:new()
  DummyHandler.super.new(self, "dummy")
end


function DummyHandler:access()
  DummyHandler.super.access(self)
end


function DummyHandler:header_filter(conf)
  DummyHandler.super.header_filter(self)

  ngx.header["Dummy-Plugin"] = conf.resp_header_value

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
