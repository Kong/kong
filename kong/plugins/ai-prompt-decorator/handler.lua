local _M = {}

-- imports
local kong_meta    = require "kong.meta"
local new_tab      = require("table.new")
local EMPTY = {}
--

_M.PRIORITY = 772
_M.VERSION = kong_meta.version


local function bad_request(msg)
  kong.log.warn(msg)
  return kong.response.exit(400, { error = { message = msg } })
end

function _M.execute(request, conf)
  local prepend = conf.prompts.prepend or EMPTY
  local append = conf.prompts.append or EMPTY

  if #prepend == 0 and #append == 0 then
    return request, nil
  end

  local old_messages = request.messages
  local new_messages = new_tab(#append + #prepend + #old_messages, 0)
  request.messages = new_messages

  local n = 0

  for _, msg in ipairs(prepend) do
    n = n + 1
    new_messages[n] = { role = msg.role, content = msg.content }
  end

  for _, msg in ipairs(old_messages) do
    n = n + 1
    new_messages[n] = msg
  end

  for _, msg in ipairs(append) do
    n = n + 1
    new_messages[n] = { role = msg.role, content = msg.content }
  end

  return request, nil
end

function _M:access(conf)
  kong.service.request.enable_buffering()
  kong.ctx.shared.prompt_decorated = true

  -- if plugin ordering was altered, receive the "decorated" request
  local err
  local request = kong.ctx.replacement_request
  if not request then
    request, err = kong.request.get_body("application/json")

    if err then
      return bad_request("ai-prompt-decorator only supports application/json requests")
    end
  end

  if not request.messages or #request.messages < 1 then
    return bad_request("ai-prompt-decorator only supports llm/chat type requests")
  end

  local decorated_request, err = self.execute(request, conf)
  if err then
    return bad_request(err)
  end
  
  -- later AI plugins looks for decorated request in thread contesxt
  kong.ctx.shared.replacement_request = decorated_request
end

return _M
