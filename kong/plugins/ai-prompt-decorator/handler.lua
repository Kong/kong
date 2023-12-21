local _M = {}

-- imports
local kong_meta      = require "kong.meta"
local access_handler = require("kong.plugins.ai-prompt-decorator.access")
local re_match       = ngx.re.match
local re_find        = ngx.re.find
local fmt            = string.format
local table_insert   = table.insert
--

_M.PRIORITY = 772
_M.VERSION = kong_meta.version


local function do_bad_request(msg)
  kong.log.warn(msg)
  kong.response.exit(400, { error = true, message = msg })
end


local function do_internal_server_error(msg)
  kong.log.err(msg)
  kong.response.exit(500, { error = true, message = msg })
end


function _M:access(conf)
  kong.log.debug("IN: ai-prompt-decorator/access")
  kong.service.request.enable_buffering()
  kong.ctx.shared.prompt_decorated = true

  -- if plugin ordering was altered, receive the "decorated" request
  local request, err
  if not kong.ctx.replacement_request then
    request, err = kong.request.get_body("application/json")

    if err then
      do_bad_request("ai-prompt-decorator only supports application/json requests")
    end
  else
    request = kong.ctx.replacement_request
  end

  if not request.messages or #request.messages < 1 then
    do_bad_request("ai-prompt-decorator only support llm/chat type requests")
  end

  -- run access handler to decorate the messages[] block
  local code, err = access_handler.execute(request, conf)
  if err then
    -- don't run header_filter and body_filter from ai-proxy plugin
    kong.ctx.shared.skip_response_transformer = true
    
    if code == 500 then kong.log.err(err) end
    kong.response.exit(code, err)
  end

  -- stash the result for parsing later (in ai-proxy)
  kong.ctx.shared.replacement_request = request
  
  -- all good
  kong.log.debug("OUT: ai-prompt-decorator/access")
end


return _M
