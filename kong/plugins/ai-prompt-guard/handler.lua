-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local buffer = require("string.buffer")
local ngx_re_find = ngx.re.find
local EMPTY = {}



local plugin = {
  PRIORITY = 771,
  VERSION = require("kong.meta").core_version
}



local function bad_request(msg)
  kong.log.debug(msg)
  return kong.response.exit(400, { error = { message = msg } })
end



local execute do
  local bad_format_error = "ai-prompt-guard only supports llm/v1/chat or llm/v1/completions prompts"

  -- Checks the prompt for the given patterns.
  -- _Note_: if a regex fails, it returns a 500, and exits the request.
  -- @tparam table request The deserialized JSON body of the request
  -- @tparam table conf The plugin configuration
  -- @treturn[1] table The decorated request (same table, content updated)
  -- @treturn[2] nil
  -- @treturn[2] string The error message
  function execute(request, conf)
    local user_prompt

    -- concat all 'user' prompts into one string, if conversation history must be checked
    if type(request.messages) == "table" and not conf.allow_all_conversation_history then
      local buf = buffer.new()

      for _, v in ipairs(request.messages) do
        if type(v.role) ~= "string" then
          return nil, bad_format_error
        end
        if v.role == "user" then
          if type(v.content) ~= "string" then
            return nil, bad_format_error
          end
          buf:put(v.content)
        end
      end

      user_prompt = buf:get()

    elseif type(request.messages) == "table" then
      -- just take the trailing 'user' prompt
      for _, v in ipairs(request.messages) do
        if type(v.role) ~= "string" then
          return nil, bad_format_error
        end
        if v.role == "user" then
          if type(v.content) ~= "string" then
            return nil, bad_format_error
          end
          user_prompt = v.content
        end
      end

    elseif type(request.prompt) == "string" then
      user_prompt = request.prompt

    else
      return nil, bad_format_error
    end

    if not user_prompt then
      return nil, "no 'prompt' or 'messages' received"
    end


    -- check the prompt for explcit ban patterns
    for _, v in ipairs(conf.deny_patterns or EMPTY) do
      -- check each denylist; if prompt matches it, deny immediately
      local m, _, err = ngx_re_find(user_prompt, v, "jo")
      if err then
        -- regex failed, that's an error by the administrator
        kong.log.err("bad regex pattern '", v ,"', failed to execute: ", err)
        return kong.response.exit(500)

      elseif m then
        return nil, "prompt pattern is blocked"
      end
    end


    if #(conf.allow_patterns or EMPTY) == 0 then
      -- no allow_patterns, so we're good
      return true
    end

    -- if any allow_patterns specified, make sure the prompt matches one of them
    for _, v in ipairs(conf.allow_patterns or EMPTY) do
      -- check each denylist; if prompt matches it, deny immediately
      local m, _, err = ngx_re_find(user_prompt, v, "jo")

      if err then
        -- regex failed, that's an error by the administrator
        kong.log.err("bad regex pattern '", v ,"', failed to execute: ", err)
        return kong.response.exit(500)

      elseif m then
        return true  -- got a match so is allowed, exit early
      end
    end

    return false, "prompt doesn't match any allowed pattern"
  end
end



function plugin:access(conf)
  kong.service.request.enable_buffering()
  kong.ctx.shared.ai_prompt_guarded = true -- future use

  -- if plugin ordering was altered, receive the "decorated" request
  local request = kong.request.get_body("application/json", nil, conf.max_request_body_size)
  if type(request) ~= "table" then
    return bad_request("this LLM route only supports application/json requests")
  end

  -- run access handler
  local ok, err = execute(request, conf)
  if not ok then
    kong.log.debug(err)
    return bad_request("bad request") -- don't let users know 'ai-prompt-guard' is in use
  end
end



if _G._TEST then
  -- only if we're testing export this function (using a different name!)
  plugin._execute = execute
end


return plugin
