local _M = {}

-- imports
local access_handler = require("kong.plugins.ai-prompt-guard.access")
--

_M.PRIORITY = 773
_M.VERSION = kong_meta.version

function _M:access(conf)
  kong.log.debug("IN: ai-prompt-guard/access")
  kong.ctx.shared.prompt_guarded = true

  local request, err = kong.request.get_body("application/json")
  if err then
    do_bad_request("ai-prompt-guard only supports application/json requests")
  end

  -- run access handler
  local code, err = access_handler.execute(request, conf)
  if err then
    if code == 500 then kong.log.err(err) end
    kong.response.exit(code, err)
  end

  -- continue is access module doesn't exit
  kong.log.debug("OUT: ai-prompt-guard/access")
end

return _M
