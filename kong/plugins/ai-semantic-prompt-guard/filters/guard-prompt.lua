
-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local buffer = require("string.buffer")
local guard = require("kong.plugins.ai-semantic-prompt-guard.guard")
local vectordb = require("kong.llm.vectordb")
local ai_plugin_ctx = require("kong.llm.plugin.ctx")
local cjson = require("cjson")

local _M = {
  NAME = "semantic-guard-prompt",
  STAGE = "REQ_TRANSFORMATION",
  }

local FILTER_OUTPUT_SCHEMA = {
  guarded = "boolean",
}

local _, set_ctx = ai_plugin_ctx.get_namespaced_accesors(_M.NAME, FILTER_OUTPUT_SCHEMA)

local function bad_request(msg)
  kong.log.debug(msg)
  return kong.response.exit(400, { error = { message = msg } })
end

local execute do
  local bad_format_error = "ai-semantic-prompt-guard only supports llm/v1/chat or llm/v1/completions prompts"

  -- Checks the prompt for the given patterns.
  -- _Note_: if a regex fails, it returns a 500, and exits the request.
  -- @tparam table request The deserialized JSON body of the request
  -- @tparam table conf The plugin configuration
  -- @treturn[1] table The decorated request (same table, content updated)
  -- @treturn[2] nil
  -- @treturn[2] string The error message
  function execute(request, conf)
    local collected_prompts
    local messages = request.messages

    -- concat all prompts into one string, if conversation history must be checked
    if type(messages) == "table" then
      local buf = buffer.new()

      -- iterate in reverse so we get the latest user prompt first
      -- instead of the oldest one in history
      for i=#messages, 1, -1 do
        local v = messages[i]
        if type(v.role) ~= "string" then
          return nil, bad_format_error
        end
        if v.role == "user" or conf.rules.match_all_roles then
          if type(v.content) == "string" then
            buf:put(v.content)
          elseif type(v.content) == "table" then
            local content = cjson.encode(v.content)
            buf:put(content)
          else
            return nil, bad_format_error
          end

          if not conf.rules.match_all_conversation_history then
            break
          end

          buf:put(" ") -- put a seperator to avoid adhension of words
        end
      end

      collected_prompts = buf:get()

    elseif type(request.prompt) == "string" then
      collected_prompts = request.prompt

    else
      return nil, bad_format_error
    end

    if not collected_prompts then
      return nil, "no 'prompt' or 'messages' received"
    end

    local guard, err = guard.get_guard_instance(conf, false)
    if err or not guard then
      return nil, "unable to get guard instance: " .. (err or "nil")
    end

    local embedding, err = guard.embeddings:generate(collected_prompts)
    if not embedding then
      return nil, "unable to generate embeddings for request: " .. (err or "nil")
    end


    local namespace = "ai-semantic-prompt-guard:" .. conf.__plugin_id
    local allow_namespace = namespace .. ":allow"
    local deny_namespace = namespace .. ":deny"
    local allow_semanticdb, err = vectordb.new(conf.vectordb.strategy, allow_namespace, conf.vectordb)
    if err then
      return nil, "unable to create vectordb:" .. err
    end
    if not allow_semanticdb then
      return nil, "unable to create vectordb"
    end

    local deny_semanticdb, err = vectordb.new(conf.vectordb.strategy, deny_namespace, conf.vectordb)
    if err then
      return nil, "unable to create vectordb:" .. err
    end
    if not deny_semanticdb then
      return nil, "unable to create vectordb"
    end

    local out = {}
    local res
    if #(conf.rules.deny_prompts or {}) > 0 then
      res = deny_semanticdb:search(embedding, conf.vectordb.threshold, out)
    end

    if res == nil then
      res = allow_semanticdb:search(embedding, conf.vectordb.threshold, out)
    end

    if res == nil then
      if #(conf.rules.allow_prompts or {}) == 0 then
        -- no allow_patterns, so we're good
        return true
      else
        return false, "prompt doesn't match any allowed pattern"
      end
    end

    if res.action == "deny" then
      return false, "prompt pattern is blocked"
    end

    if res.action == "allow" then
      return true
    end

    -- should not reach here
    return false, "unexcepted action in matched rule"
  end
end

function _M:run(conf)
  -- if plugin ordering was altered, receive the "decorated" request
  local request_body_table = ai_plugin_ctx.get_request_body_table_inuse()
  if not request_body_table then
    return bad_request("this LLM route only supports application/json requests")
  end

  -- run access handler
  local ok, err = execute(request_body_table, conf)
  if not ok then
    kong.log.debug(err)
    return bad_request("bad request") -- don't let users know 'ai-prompt-guard' is in use
  end

  set_ctx("guarded", true)

  return true
end

return _M