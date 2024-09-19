-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local kong_meta       = require("kong.meta")
local vectordb        = require("kong.llm.vectordb")
local embeddings      = require("kong.ai.embeddings")
local buffer          = require("string.buffer")
local sha256_hex      = require "kong.tools.sha256".sha256_hex
local ai_shared       = require("kong.llm.drivers.shared")
local deep_copy       = require("kong.tools.table").deep_copy
local cjson           = require("cjson.safe")
local llm_state       = require("kong.llm.state")
local parse_directive_header = require("kong.tools.http").parse_directive_header
local calculate_resource_ttl = require("kong.tools.http").calculate_resource_ttl

local kong          = kong
local ngx           = ngx
local floor         = math.floor

local AISemanticCaching = {
  PRIORITY = 765, -- leave space for other response-interceptor AI plugins
  VERSION = kong_meta.core_version
}

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

local SEMANTIC_CACHE_NAMESPACE_PREFIX = "kong_semantic_cache:"

local STATUS_HIT = "Hit"
local STATUS_MISS = "Miss"
local STATUS_REFRESH = "Refresh"
local STATUS_BYPASS = "Bypass"
local STATUS_FAILED = "Failed"

local function set_cache_status(status)
  llm_state.set_semantic_cache_hit(status == STATUS_HIT)
  kong.log.debug("Semantic cache: ", status)
  kong.ctx.plugin.cache_status = status
  kong.response.set_header("X-Cache-Status", status)
end

-- Helper function to log warnings and return a 400 response
local function bad_request(conf, err, msg)
  if err then 
    kong.log.warn("" .. err)
  end

  set_cache_status(STATUS_FAILED)
  return kong.response.exit(400, { message = msg })
end

-- Validates incoming request format
local function validate_incoming(request)
  return request
    and type(request) == "table"
    and request.messages
    and type(request.messages) == "table"
    and #request.messages > 0
end

-- Retrieves request Cache-Control directives
local function req_cc()
  return parse_directive_header(ngx.var.http_cache_control)
end

-- Retrieves response Cache-Control directives
local function res_cc()
  return parse_directive_header(ngx.var.sent_http_cache_control)
end

-- Checks if the response is cacheable based on Cache-Control directives
local function cacheable_response(conf, cc)
  if conf.cache_control and (cc["private"] or cc["no-store"] or cc["no-cache"]) then
    return false
  end

  if conf.cache_control and calculate_resource_ttl(cc) <= 0 then
    return false
  end

  return true
end

-- Checks if the request is cacheable based on Cache-Control directives
local function cacheable_request(conf, cc)
  if conf.cache_control and (cc["no-store"] or cc["no-cache"] or ngx.var.authorization) then
    return false
  end

  return true
end

-- Formats chat messages into a vectorizable string
local function format_chat(messages, countback, discard_system, discard_assistant)
  local buf = buffer.new()

  for i = #messages, #messages - countback + 1, -1 do
    local message = messages[i]
    if message then
      if message.role == "system" and not discard_system then
        buf:putf("%s: %s\n\n", message.role, message.content)
      elseif message.role == "assistant" and not discard_assistant then
        buf:putf("%s: %s\n\n", message.role, message.content)
      elseif message.role == "user" then
        buf:putf("%s\n\n", message.content)
      end
    end
  end

  return buf:get()
end

local function stash_stats(conf, start_time, embeddings_latency, embeddings_tokens, saving_prompt_tokens, saving_completion_tokens)
  local aip_conf = llm_state.get_ai_proxy_conf()
  if not aip_conf then
    return
  end

  -- update timer for latency calculation
  ngx.update_time()

  local cache_metrics = {
    vector_db = conf.vectordb.driver,
    cache_status = kong.ctx.plugin.cache_status,
  }

  if start_time then
    cache_metrics.fetch_latency = math.floor((ngx.now() - start_time) * 1000)
  end

  if embeddings_latency then
    cache_metrics.embeddings_latency = math.floor(embeddings_latency * 1000)
    cache_metrics.embeddings_provider = conf.embeddings.model.provider
    cache_metrics.embeddings_model = conf.embeddings.model.name
  end

  if saving_prompt_tokens and saving_completion_tokens and aip_conf.model and aip_conf.model.options
    and aip_conf.model.options.input_cost and aip_conf.model.options.output_cost then
    cache_metrics.cost_savings = (
      (aip_conf.model.options.input_cost * saving_prompt_tokens) +
      (aip_conf.model.options.output_cost * saving_completion_tokens)
    ) / 1000000
  end

  if embeddings_tokens then
    cache_metrics.embeddings_tokens = embeddings_tokens
  end

  assert(ai_shared.stash_cache_stats(aip_conf, cache_metrics))
end

local function post_request(response_body)
  local aip_conf = llm_state.get_ai_proxy_conf()
  if not aip_conf then
    return
  end

  -- if response_body is passed in, we are in error handling
  -- create an empty response object
  response_body = response_body or {}

  response_body.usage = {
    prompt_tokens = 0,
    completion_tokens = 0,
    total_tokens = 0,
  }

  ai_shared.post_request(aip_conf, response_body)
end

local function send_cache_response(conf, cache_response, stream_mode, start_time, embeddings_latency, embeddings_tokens, metadata)
  cache_response = assert(cjson.decode(cache_response))

  local cc = req_cc()

  local ttl = conf.cache_control and calculate_resource_ttl(cc) or
                conf.cache_ttl

  local cache_age = cache_response.ttl and (ttl - cache_response.ttl) or 0
  local max_age = conf.cache_ttl - cache_age

  if max_age <= 0 then
    set_cache_status(STATUS_REFRESH)
    return
  end

  set_cache_status(STATUS_HIT)
  -- mimic the proxy handler behaviour to popluate statistics
  local saving_prompt_tokens = cache_response.usage.prompt_tokens
  local saving_completion_tokens = cache_response.usage.completion_tokens
  post_request(cache_response)
  stash_stats(conf, start_time, embeddings_latency, embeddings_tokens, saving_prompt_tokens, saving_completion_tokens)

  kong.response.set_header("Age", floor(cache_age))
  if metadata.key then kong.response.set_header("X-Cache-Key", metadata.key) end
  if metadata.ttl then kong.response.set_header("X-Cache-Ttl", metadata.ttl) end

  if stream_mode then
    ngx.status = 200
    ngx.header["content-type"] = "text/event-stream"

    if not cache_response or not cache_response.choices
      or not cache_response.choices[1] or not cache_response.choices[1].message
      or not cache_response.choices[1].message.content then
        kong.response.exit(500, { message = "Illegal stream chat message" })
    end

    -- create a duplicated response frame
    local content = deep_copy(_STREAM_CHAT_MESSAGE)
    content.choices[1].delta.content = cache_response.choices[1].message.content
    content.model = cache_response.model
    content.id = metadata.key
    content.choices[1].finish_reason = cache_response.choices[1].finish_reason
    content = cjson.encode(content)
    ngx.print("data: " .. content)
    ngx.print("\n\n")

    -- now create a duplicated finish_reason frame
    content = deep_copy(_STREAM_CHAT_MESSAGE)
    content.model = cache_response.model
    content.id = metadata.key
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
    kong.service.request.enable_buffering()
    cache_response.id = metadata.key
    return kong.response.exit(200, cache_response, { ["Content-Type"] = "application/json; charset=utf-8" })
  end
end

-- Access phase for semantic caching
function AISemanticCaching:access(conf)
  local start_time = ngx.now()
  kong.ctx.plugin.start_time = start_time

  local cc = req_cc()

  if not cacheable_request(conf, cc) then
    set_cache_status(STATUS_BYPASS)
    return
  end

  local model = "NOT_SPECIFIED"
  -- parse from ai-proxy-* conf
  local aip_conf = llm_state.get_ai_proxy_conf()
  if aip_conf and aip_conf.model then
    model = aip_conf.model.provider .. "-" .. llm_state.get_request_model()
  end

  local namespace = SEMANTIC_CACHE_NAMESPACE_PREFIX .. conf.__plugin_id .. ":" .. model

  local vectordb_driver, err = vectordb.new(conf.vectordb.strategy, namespace, conf.vectordb)
  if err then
    if conf.stop_on_failure then
      -- Exit the request early
      llm_state.set_semantic_cache_hit(true)
      return bad_request(conf, err, "Failed to load the '" .. conf.vectordb.strategy .. "' vector database driver")
    end

    -- Continue regardless of error, but break from the plugin
    kong.log.warn("Failed to load the '", conf.vectordb.strategy, "' vector database driver: ", err, ", plugin config is set to continue on failure")
    return
  end

  kong.log.debug("Parsing prompt from request body")

  local request_table = llm_state.get_request_body_table()

  if not validate_incoming(request_table) then
    -- Plugin is enabled by accident or non-AI request
    return bad_request(conf, err, "request format is not valid - check for Content-Type or JSON-completeness")
  end

  local stream_mode = request_table.stream

  local formatted_chat = format_chat(request_table.messages,
                                    conf.message_countback,
                                    conf.ignore_system_prompts,
                                    conf.ignore_assistant_prompts)

  local cache_key = sha256_hex(formatted_chat)
  kong.ctx.plugin.semantic_cache_key = cache_key
  local metadata_out = {}

  if conf.exact_caching then
    local cache_response, err = vectordb_driver:get(namespace .. ":" .. cache_key, metadata_out)
    if err then
      kong.log.debug("No data for specific prompt when doing exact caching: ", err)
    end

    if cache_response then
      -- exit and send response
      send_cache_response(conf, cache_response, stream_mode, start_time, nil, nil, metadata_out)
      return
    end
  end

  kong.log.debug("Loading the embeddings driver")
  local embeddings_driver, err = embeddings.new(conf.embeddings, conf.vectordb.dimensions)
  if err then
    if conf.stop_on_failure then
      -- Exit the request early
      llm_state.set_semantic_cache_hit(true)
      return bad_request(conf, err, "Failed to instantiate embeddings driver")
    end

    -- Continue regardless of error, but break from the plugin
    kong.log.warn("Failed to instantiate embeddings driver: ", err, ", plugin config is set to continue on failure")
    return
  end

  kong.log.debug("Generating the embeddings for the prompt")
  local embeddings_start_time = ngx.now()
  local embeddings, embeddings_tokens, err = embeddings_driver:generate(formatted_chat)

  if embeddings and (#embeddings ~= conf.vectordb.dimensions) then
    return bad_request(conf, "Embedding dimensions do not match the configured vector database. Embeddings were " ..
      #embeddings .. " dimensions, but the vector database is configured for " ..
      conf.vectordb.dimensions .. " dimensions.", "Embedding dimensions do not match the configured vector database")
  end

  if err then
    if conf.stop_on_failure then
      -- Exit the request early
      llm_state.set_semantic_cache_hit(false)
      return bad_request(conf, err, "Failed to generate embeddings")
    end

    -- Continue regardless of error, but break from the plugin
    kong.log.warn("Failed to generate embeddings: ", err, ", plugin config is set to continue on failure")
    return
  end

  -- update timer for latency calculation
  ngx.update_time()

  local embeddings_latency = ngx.now() - embeddings_start_time
  kong.ctx.plugin.semantic_cache_embeddings = embeddings
  kong.ctx.plugin.embeddings_latency = embeddings_latency

  local cache_response, err = vectordb_driver:search(embeddings, conf.vectordb.default_threshold, metadata_out)

  if err then
    if conf.stop_on_failure then
      -- Exit the request early
      llm_state.set_semantic_cache_hit(false)
      return bad_request(conf, err, "Failed to query '" .. conf.vectordb.driver .. "' for cached response")
    else
      -- Continue regardless of error, but break from the plugin
      kong.log.warn("Failed to query '" .. conf.vectordb.driver .. "' for cached response: ", err, ", plugin config is set to continue on failure")
      return
    end
  end

  -- exit and send response
  if not cache_response then
    set_cache_status(STATUS_MISS)
    stash_stats(conf, start_time, embeddings_latency, embeddings_tokens)
    -- ask ai-proxy* to buffer the stream body to be cached later
    llm_state.set_stream_body_buffer_needed()
    return
  end

  send_cache_response(conf, cache_response, stream_mode, start_time, embeddings_latency, embeddings_tokens, metadata_out)
end


-- Header filter phase for semantic caching
function AISemanticCaching:header_filter(conf)
  if llm_state.is_semantic_cache_hit() then
    return
  end

  local cc = res_cc()

  if not cacheable_response(conf, cc) then
    kong.response.set_header("X-Cache-Status", "Bypass")
    return
  end
end


-- Log filter phase for semantic caching
function AISemanticCaching:log(conf)
  local cc = res_cc()

  kong.log.debug("caching response for future requests")

  if not llm_state.is_semantic_cache_hit() then
    -- For now, the whole stream body is not buffered by ai-proxy* unless logging.log_payloads=true
    -- so we concat it on our side in body_filter phase.
    local body = llm_state.get_parsed_response()

    if not body or #body == 0 then
      kong.log.warn("No body to cache in a cache miss request")
      return
    end

    local embeddings = kong.ctx.plugin.semantic_cache_embeddings
    local cache_key = kong.ctx.plugin.semantic_cache_key
    local storage_ttl = conf.cache_control and calculate_resource_ttl(cc) or
                  conf.cache_ttl
    local model = "NOT_SPECIFIED"
    -- parse from ai-proxy-* conf
    local aip_conf = llm_state.get_ai_proxy_conf()
    if aip_conf and aip_conf.model then
      model = aip_conf.model.provider .. "-" .. llm_state.get_request_model()
    end

    local namespace = SEMANTIC_CACHE_NAMESPACE_PREFIX .. conf.__plugin_id .. ":" .. model
    ngx.timer.at(0, function(premature, conf, embeddings, body, cache_key, storage_ttl)
      if premature then
        return
      end

      local vectordb_driver, err = vectordb.new(conf.vectordb.strategy, namespace, conf.vectordb)
      if err then
        kong.log.warn("Unable to load the cache driver: ", err)
      end

      if not embeddings then
        kong.log.warn("No able to cache as no embeddings")
        return
      end

      local _, err = vectordb_driver:insert(embeddings, body, cache_key, storage_ttl)
      if err then
        kong.log.warn("Unable to store response in the cache: ", err)
      end
      kong.log.debug("Response loaded in the cache ")
    end, conf, embeddings, body, cache_key, storage_ttl)
  end
end


-- export private functions and imports for unit test mode
if _G._TEST then
  AISemanticCaching._parse_directive_header = parse_directive_header
  AISemanticCaching._stash_stats = stash_stats
  AISemanticCaching._post_request = post_request
  AISemanticCaching._validate_incoming = validate_incoming
  AISemanticCaching._format_chat = format_chat
  AISemanticCaching._set_ngx = function(new_ngx)
    ngx = new_ngx
  end
  AISemanticCaching._set_ai_shared = function(new_ai_shared)
    ai_shared = new_ai_shared
  end
end


return AISemanticCaching
