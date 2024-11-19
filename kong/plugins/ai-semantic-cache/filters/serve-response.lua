-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson = require("cjson")
local ai_plugin_ctx = require("kong.llm.plugin.ctx")
local deep_copy       = require("kong.tools.table").deep_copy
local deflate_gzip = require("kong.tools.gzip").deflate_gzip


local _M = {
  NAME = "ai-semantic-cache-serve-response",
  STAGE = "REQ_TRANSFORMATION",
  DESCRIPTION = "serve the response from cache if it's a hit",
}

local get_global_ctx, set_global_ctx = ai_plugin_ctx.get_global_accessors(_M.NAME)

local _STREAM_CHAT_MESSAGE = {
  choices = {
    {
      delta = {
        content = nil,
      },
      finish_reason = nil,
      index = 0,
      logprobs = cjson.null,
    },
  },
  id = nil,
  model = nil,
  object = "chat.completions.chunk",
}

function _M:run(_)
  local cache_status = ai_plugin_ctx.get_namespaced_ctx("ai-semantic-cache-search-cache", "cache_status")
  if cache_status ~= "Hit" then
    -- do nothing, cache not hit
    return true
  end

  local cache_response, source = get_global_ctx("response_body")
  if not cache_response then
    -- do nothing, headers are already sent
    return kong.response.exit(500, { message = "No cache response found" })
  end

  kong.log.debug("serving cached response from source: ", source)

  local cache_key = ai_plugin_ctx.get_namespaced_ctx("ai-semantic-cache-search-cache", "cache_key")
  if not cache_key then
    return true
  end

  if get_global_ctx("stream_mode") then
    ngx.status = 200
    ngx.header["content-type"] = "text/event-stream"

    cache_response = cjson.decode(cache_response)

    if not cache_response or not cache_response.choices
      or not cache_response.choices[1] or not cache_response.choices[1].message
      or not cache_response.choices[1].message.content then
        kong.response.exit(500, { message = "Illegal stream chat message" })
    end

    set_global_ctx("response_body_sent", true)

    -- create a duplicated response frame
    local content = deep_copy(_STREAM_CHAT_MESSAGE)
    content.choices[1].delta.content = cache_response.choices[1].message.content
    content.model = cache_response.model
    content.id = cache_key
    content.choices[1].finish_reason = cache_response.choices[1].finish_reason
    content = cjson.encode(content)
    ngx.print("data: " .. content)
    ngx.print("\n\n")

    -- now create a duplicated finish_reason frame
    content = deep_copy(_STREAM_CHAT_MESSAGE)
    content.model = cache_response.model
    content.id = cache_key
    content.choices[1].finish_reason = cache_response.choices[1].finish_reason
    content = cjson.encode(content)
    ngx.print("data: " .. content)
    ngx.print("\n\n")

    -- now exit
    ngx.print("data: [DONE]")

    -- need to exit here to avoid other plugin buffering proxy processing,
    -- as we are streaming the response, that will conflict with the `ngx.print` API
    return ngx.exit(ngx.OK)
  else
    if get_global_ctx("accept_gzip") then
      cache_response = deflate_gzip(cache_response)
    end

    set_global_ctx("response_body_sent", true)

    return kong.response.exit(200, cache_response, {
      ["Content-Type"] = "application/json; charset=utf-8",
      ["Content-Encoding"] = get_global_ctx("accept_gzip") and "gzip" or nil,
    })
  end
end

return _M