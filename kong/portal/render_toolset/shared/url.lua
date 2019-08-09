local url        = require "socket.url"

local Url = {}


function Url:path()
  local parsed_url = url.parse(self.ctx)
  local ctx = parsed_url.path

  return self
          :set_ctx(ctx)
          :next()
end


function Url:host()
  local parsed_url = url.parse(self.ctx)
  local ctx = parsed_url.host

  return self
          :set_ctx(ctx)
          :next()
end


function Url:protocol()
  local parsed_url = url.parse(self.ctx)
  local ctx = parsed_url.scheme

  return self
          :set_ctx(ctx)
          :next()
end

return Url
