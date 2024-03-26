local _M = {}

-- imports
local kong_meta   = require "kong.meta"
local buffer      = require("string.buffer")
local ngx_re_find = ngx.re.find
--

_M.PRIORITY = 771
_M.VERSION = kong_meta.version

local function bad_request(msg, reveal_msg_to_client)
  -- don't let users know 'ai-prompt-guard' is in use
  kong.log.info(msg)
  if not reveal_msg_to_client then
    msg = "bad request"
  end
  return kong.response.exit(400, { error = { message = msg } })
end

function _M.execute(request, conf)
  local user_prompt

  -- concat all 'user' prompts into one string, if conversation history must be checked
  if request.messages and not conf.allow_all_conversation_history then
    local buf = buffer.new()

    for _, v in ipairs(request.messages) do
      if v.role == "user" then
        buf:put(v.content)
      end
    end

    user_prompt = buf:get()

  elseif request.messages then
    -- just take the trailing 'user' prompt
    for _, v in ipairs(request.messages) do
      if v.role == "user" then
        user_prompt = v.content
      end
    end

  elseif request.prompt then
    user_prompt = request.prompt

  else
    return nil, "ai-prompt-guard only supports llm/v1/chat or llm/v1/completions prompts"
  end

  if not user_prompt then
    return nil, "no 'prompt' or 'messages' received"
  end

  -- check the prompt for explcit ban patterns
  if conf.deny_patterns and #conf.deny_patterns > 0 then
    for _, v in ipairs(conf.deny_patterns) do
      -- check each denylist; if prompt matches it, deny immediately
      local m, _, err = ngx_re_find(user_prompt, v, "jo")
      if err then
        return nil, "bad regex execution for: " .. v

      elseif m then
        return nil, "prompt pattern is blocked"
      end
    end
  end

  -- if any allow_patterns specified, make sure the prompt matches one of them
  if conf.allow_patterns and #conf.allow_patterns > 0 then
    local valid = false

    for _, v in ipairs(conf.allow_patterns) do
      -- check each denylist; if prompt matches it, deny immediately
      local m, _, err = ngx_re_find(user_prompt, v, "jo")

      if err then
        return nil, "bad regex execution for: " .. v

      elseif m then
        valid = true
        break
      end
    end

    if not valid then
      return false, "prompt doesn't match any allowed pattern"
    end
  end

  return true, nil
end

function _M:access(conf)
  kong.service.request.enable_buffering()
  kong.ctx.shared.ai_prompt_guarded = true -- future use

  -- if plugin ordering was altered, receive the "decorated" request
  local request, err = kong.request.get_body("application/json")

  if err then
    return bad_request("this LLM route only supports application/json requests", true)
  end

  -- run access handler
  local ok, err = self.execute(request, conf)
  if not ok then
    return bad_request(err, false)
  end
end

return _M
