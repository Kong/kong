local _M = {}

-- imports
local kong_meta = require "kong.meta"
local access_handler = require("kong.plugins.ai-prompt-guard.access")
--

_M.PRIORITY = 771
_M.VERSION = kong_meta.version

function _M:access(conf)
  kong.log.debug("IN: ai-prompt-guard/access")
  kong.service.request.enable_buffering()
  kong.ctx.shared.prompt_guarded = true

  -- if plugin ordering was altered, receive the "decorated" request
  local request, err
  if not kong.ctx.replacement_request then
    request, err = kong.request.get_body("application/json")

    if err then
      do_bad_request("ai-prompt-guard only supports application/json requests")
    end
  else
    request = kong.ctx.replacement_request
  end

  -- run access handler
  local code, err = access_handler.execute(request, conf)
  if err then
    -- don't run header_filter and body_filter from ai-proxy plugin
    kong.ctx.shared.skip_response_transformer = true
    
    if code == 500 then kong.log.err(err) end
    kong.response.exit(code, err)
  end

  -- continue if access module doesn't exit early
  kong.log.debug("OUT: ai-prompt-guard/access")
end

return _M
