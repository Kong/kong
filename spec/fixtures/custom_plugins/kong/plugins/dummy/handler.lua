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
end


return DummyHandler
