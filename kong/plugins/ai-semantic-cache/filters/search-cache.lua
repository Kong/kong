-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson           = require("cjson")
local vectordb        = require("kong.llm.vectordb")
local embeddings      = require("kong.llm.embeddings")
local buffer          = require("string.buffer")
local parse_directive_header = require("kong.tools.http").parse_directive_header
local calculate_resource_ttl = require("kong.tools.http").calculate_resource_ttl
local sha256_hex      = require "kong.tools.sha256".sha256_hex
local ai_plugin_ctx = require("kong.llm.plugin.ctx")
local ai_plugin_o11y = require("kong.llm.plugin.observability")

local floor         = math.floor


local _M = {
  NAME = "ai-semantic-cache-search-cache",
  STAGE = "REQ_TRANSFORMATION",
  DESCRIPTION = "semantically match the request against the cache",
}

local FILTER_OUTPUT_SCHEMA = {
  cache_status = "string",
  cache_key = "string",
  embeddings_vector = "table",
  vectordb_namespace = "string",

  -- metrics
  embeddings_latency = "number",
  embeddings_tokens_count = "number",
  cache_fetch_latency = "number",
}


local _, set_global_ctx = ai_plugin_ctx.get_global_accessors(_M.NAME)
local _, set_ctx = ai_plugin_ctx.get_namespaced_accesors(_M.NAME, FILTER_OUTPUT_SCHEMA)


local STATUS_HIT = "Hit"
local STATUS_MISS = "Miss"
local STATUS_REFRESH = "Refresh"
local STATUS_BYPASS = "Bypass"
local STATUS_FAILED = "Failed"
local SEMANTIC_CACHE_NAMESPACE_PREFIX = "kong_semantic_cache:"

-- Retrieves request Cache-Control directives
local function req_cc()
  return parse_directive_header(ngx.var.http_cache_control)
end

-- Checks if the request is cacheable based on Cache-Control directives
local function cacheable_request(conf, cc)
  if conf.cache_control and (cc["no-store"] or cc["no-cache"] or ngx.var.authorization) then
    return false
  end

  return true
end

local function set_cache_status(status)
  kong.log.debug("Semantic cache: ", status)
  set_ctx("cache_status", status)
  kong.response.set_header("X-Cache-Status", status)

  if status == STATUS_MISS or status == STATUS_REFRESH then
    set_global_ctx("sse_body_buffer", buffer.new())
  end

  return true
end

-- Formats chat messages into a vectorizable string
local function format_chat(messages, countback, discard_system, discard_assistant, discard_tool)
  if not messages then
    return ""
  end

  local buf = buffer.new()
  local content

  for i = #messages, #messages - countback + 1, -1 do
    local message = messages[i]
    if message then
      if message.role == "system" and not discard_system then
        if type(message.content) == "table" then
          content = cjson.encode(message.content)
        else
          content = message.content
        end
        buf:putf("%s: %s\n\n", message.role, content)
      elseif message.role == "assistant" and not discard_assistant then
        if type(message.content) == "table" then
          content = cjson.encode(message.content)
        else
          content = message.content
        end
        buf:putf("%s: %s\n\n", message.role, content)
      elseif message.role == "user" then
        if type(message.content) == "table" then
          content = cjson.encode(message.content)
        else
          content = message.content
        end
        buf:putf("%s: %s\n\n", message.role, content)
      elseif message.role == "tool" and not discard_tool then
        if type(message.content) == "table" then
          content = cjson.encode(message.content)
        else
          content = message.content
        end
        buf:putf("%s: %s\n\n", message.role, content)
      end
    end
  end

  return buf:get()
end

-- Helper function to log warnings and return a 400 response
local function bail(code, msg)
  set_cache_status(STATUS_FAILED)
  kong.response.exit(code, { message = msg })
  return true
end

local function check_error(conf, err, message)
  if not err then
    return
  end

  if conf.stop_on_failure then
    return bail(500, message)
  end

  kong.log.warn(message, ": ", err)
end

local function handle_cache_hit(conf, filter_start_time, metadata, cache_response)
  set_cache_status(STATUS_HIT)
  set_global_ctx("response_body", cjson.encode(cache_response))

  -- o11y
  do
    ngx.update_time()

    ai_plugin_o11y.metrics_set("llm_e2e_latency", math.floor(ngx.now() - filter_start_time) * 1000)

    local completion_tokens_count = cache_response and cache_response.usage and cache_response.usage.completion_tokens
    if completion_tokens_count and completion_tokens_count > 0 then
      ai_plugin_o11y.metrics_set("llm_completion_tokens_count", completion_tokens_count)
    end

    local prompt_tokens_count = cache_response and cache_response.usage and cache_response.usage.prompt_tokens
    if prompt_tokens_count then
      ai_plugin_o11y.metrics_set("llm_prompt_tokens_count", prompt_tokens_count)
    end
  end

  -- response handling
  local cc = req_cc()
  local ttl = conf.cache_control and calculate_resource_ttl(cc) or
                conf.cache_ttl

  local cache_age = cache_response.ttl and (ttl - cache_response.ttl) or 0
  local max_age = conf.cache_ttl - cache_age

  if max_age <= 0 then
    return set_cache_status(STATUS_REFRESH)
  end

  kong.response.set_header("Age", floor(cache_age))
  if metadata.key then
    kong.response.set_header("X-Cache-Key", metadata.key)
  end

  if metadata.ttl then
    kong.response.set_header("X-Cache-Ttl", metadata.ttl)
  end

  return true
end

function _M:run(conf)
  local filter_start_time = ngx.now()

  local cc = req_cc()

  if not cacheable_request(conf, cc) then
    return set_cache_status(STATUS_BYPASS)
  end

  -- load request body
  local request_body_table = ai_plugin_ctx.get_request_body_table_inuse()

  if not request_body_table then
    return bail(400, "Failed to read request body")
  end

  if not request_body_table.messages then
    return bail(400, "Not a valid llm/chat request")
  end

  local formatted_chat = format_chat(request_body_table.messages,
                                    conf.message_countback,
                                    conf.ignore_system_prompts,
                                    conf.ignore_assistant_prompts,
                                    conf.ignore_tool_prompts)

  local err

  -- vectordb driver init
  local vectordb_driver, vectordb_namespace
  do
    local model_t = ai_plugin_ctx.get_request_model_table_inuse()
    local suffix = model_t and model_t.provider or "UNSPECIFIED"

    if model_t.name then
      suffix = suffix .. "-" .. model_t.name
    end

    vectordb_namespace = SEMANTIC_CACHE_NAMESPACE_PREFIX .. conf.__plugin_id .. ":" .. suffix
    set_ctx("vectordb_namespace", vectordb_namespace)
    vectordb_driver, err = vectordb.new(conf.vectordb.strategy, vectordb_namespace, conf.vectordb)

    check_error(conf, err, "Failed to load the '" .. conf.vectordb.strategy .. "' vector database driver")

    -- if error and stop_on_failure is not set, just return as we can't do cache search and cache store
    if not vectordb_driver then
      return set_cache_status(STATUS_BYPASS)
    end
  end

  -- exact match
  local cache_key = sha256_hex(formatted_chat)
  set_ctx("cache_key", cache_key)
  local metadata_out = {}

  if conf.exact_caching then
    local cache_fetch_start_time = ngx.now()
    local cache_response, err = vectordb_driver:get(vectordb_namespace .. ":" .. cache_key, metadata_out)
    if err then
      kong.log.debug("No data for specific prompt when doing exact caching: ", err)
    end

    if cache_response then
      ngx.update_time()
      set_ctx("cache_fetch_latency", math.floor(ngx.now() - cache_fetch_start_time) * 1000)
      return handle_cache_hit(conf, filter_start_time, metadata_out, cache_response)
    end
  end

  -- embeddings init
  local embeddings_vector
  do
    local embeddings_driver, err = embeddings.new(conf.embeddings, conf.vectordb.dimensions)
    check_error(conf, err, "Failed to instantiate embeddings driver")

    kong.log.debug("Generating the embeddings for the prompt")
    local embeddings_start_time = ngx.now()
    local embeddings_tokens_count
    embeddings_vector, embeddings_tokens_count, err = embeddings_driver:generate(formatted_chat)
    check_error(conf, err, "Failed to generate embeddings")

    if not embeddings_vector then
      set_cache_status(STATUS_FAILED)
    elseif #embeddings_vector ~= conf.vectordb.dimensions then
      return bail(500, "Embedding dimensions do not match the configured vector database. Embeddings were " ..
        #embeddings_vector .. " dimensions, but the vector database is configured for " ..
        conf.vectordb.dimensions .. " dimensions.", "Embedding dimensions do not match the configured vector database")
    end

    -- update timer for latency calculation
    ngx.update_time()
    set_ctx("embeddings_latency", math.floor(ngx.now() - embeddings_start_time) * 1000)

    set_ctx("embeddings_tokens_count", embeddings_tokens_count or 0)
    set_ctx("embeddings_vector", embeddings_vector or {})
  end

  -- semantic match
  local cache_fetch_start_time = ngx.now()
  local cache_response, err = vectordb_driver:search(embeddings_vector, conf.vectordb.default_threshold, metadata_out)
  check_error(conf, err, "Failed to query '" .. conf.vectordb.strategy .. "' for cached response")

   -- exit and send response
  if not cache_response then
    return set_cache_status(STATUS_MISS)
  end


  ngx.update_time()
  set_ctx("cache_fetch_latency", math.floor(ngx.now() - cache_fetch_start_time) * 1000)
  -- finally, cache hit
  return handle_cache_hit(conf, filter_start_time, metadata_out, cache_response)
end


if _G._TEST then
  _M._parse_directive_header = parse_directive_header
  _M._calculate_resource_ttl = calculate_resource_ttl
  _M._format_chat = format_chat
end


return _M