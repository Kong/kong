local _M = {
  NAME = "enable-buffering",
  STAGE = "REQ_INTROSPECTION",
  DESCRIPTION = "set the response to buffering mode",
}

local ai_plugin_ctx = require("kong.llm.plugin.ctx")
local get_global_ctx, _ = ai_plugin_ctx.get_global_accessors(_M.NAME)

function _M:run(_)
  if ngx.get_phase() == "access" and (not get_global_ctx("stream_mode")) then
    kong.service.request.enable_buffering()
  end

  return true
end

return _M
