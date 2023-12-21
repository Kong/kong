local _M = {}

-- imports
local kong_meta    = require "kong.meta"
local re_match     = ngx.re.match
local re_find      = ngx.re.find
local fmt          = string.format
local table_insert = table.insert
--

_M.PRIORITY = 772
_M.VERSION = kong_meta.version

local function to_chat_prompt(version, role, content)
  if version == "v1" then
    return { role = role, content = content }
  else
    return nil
  end
end

function _M.execute(request, conf) 
  -- 1. add in-order to the head of the chat
  if conf.prompts.prepend and #conf.prompts.prepend > 0 then
    for i, v in ipairs(conf.prompts.prepend) do
      table.insert(request.messages, i, to_chat_prompt("v1", v.role, v.content))
    end
  end

  -- 2. add in-order to the tail of the chat
  if conf.prompts.append and #conf.prompts.append > 0 then
    local messages_length = #request.messages

    for i, v in ipairs(conf.prompts.append) do
      request.messages[i + messages_length] = to_chat_prompt("v1", v.role, v.content)
    end
  end
  
  return nil, nil
end

return _M
