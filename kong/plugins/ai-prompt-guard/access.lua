local _M = {}

--imports
local fmt = string.format

local function do_bad_request(msg)
  return 400, { error = true, message = msg }
end

local function do_internal_server_error(msg)
  return 500, { error = true, message = msg }
end

function _M.execute(request, conf)
  local user_prompt

  -- concat all 'user' prompts into one string, if allowed
  if request.messages and not conf.allow_all_conversation_history then
    for k, v in ipairs(request.messages) do
      if v.role == "user" then
        if not user_prompt then user_prompt = "" end
        user_prompt = fmt("%s %s", user_prompt, v.content)
      end
    end
  elseif request.messages then
    -- just take the trailing 'user' prompt
    for k, v in ipairs(request.messages) do
      if v.role == "user" then
        user_prompt = v.content
      end
    end
  elseif request.prompt then
    user_prompt = request.prompt
  else
    return do_bad_request("ai-prompt-guard only supports llm/v1/chat or llm/v1/completions prompts")
  end

  if not user_prompt then
    return do_bad_request("no 'prompt' or 'messages' received")
  end

  -- check the prompt for explcit ban patterns
  if conf.deny_patterns and #conf.deny_patterns > 0 then
    for i, v in ipairs(conf.deny_patterns) do
      -- check each denylist; if prompt matches it, deny immediately
      local m, err = ngx.re.match(user_prompt, v)
      if err then return do_internal_server_error("bad regex execution for: " .. v) end

      if m then return do_bad_request("prompt pattern is blocked") end
    end
  end

  -- if any allow_patterns specified, make sure the prompt matches one of them
  if conf.allow_patterns and #conf.allow_patterns > 0 then
    local valid = false

    for i, v in ipairs(conf.allow_patterns) do
      -- check each denylist; if prompt matches it, deny immediately
      local m, err = ngx.re.match(user_prompt, v)

      if err then return do_bad_request("bad regex execution for: " .. v) end

      if m then valid = true end
    end

    if not valid then return do_bad_request("prompt doesn't match any allowed pattern") end
  end

  return nil, nil
end

return _M
