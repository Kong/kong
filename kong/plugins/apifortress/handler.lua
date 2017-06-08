-- The plugin handler

local forward = require "kong.plugins.apifortress.forward"
local BasePlugin = require "kong.plugins.base_plugin"

local ApiFortressHandler = BasePlugin:extend()

function ApiFortressHandler:new()
  ApiFortressHandler.super.new(self, "apifortress-filter")
end
function ApiFortressHandler:access(conf)
  ngx.req.read_body()
end

function ApiFortressHandler:log(conf)
  ApiFortressHandler.super.log(self)
  forward.execute(conf)
end

function ApiFortressHandler:body_filter(config)
  ApiFortressHandler.super.body_filter(self)

  -- Capturing response body
  local chunk, eof = ngx.arg[1], ngx.arg[2]
  local captured_body = ngx.ctx.captured_body
  if not captured_body then
    captured_body = {}
    ngx.ctx.captured_body = captured_body
  end
  captured_body[#captured_body + 1] = chunk
  if eof then
    ngx.ctx.captured_body = table.concat(captured_body)
  end

end
ApiFortressHandler.PRIORITY = 800

return ApiFortressHandler
