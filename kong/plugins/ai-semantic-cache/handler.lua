-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local kong_meta       = require("kong.meta")
local vectordb        = require("kong.llm.vectordb")
local embeddings      = require("kong.ai.embeddings")
local split           = require("kong.tools.string").split
local buffer          = require("string.buffer")
local sha256_hex      = require "kong.tools.sha256".sha256_hex
local ai_shared       = require("kong.llm.drivers.shared")
local deep_copy       = require("kong.tools.table").deep_copy
local parse_http_time = ngx.parse_http_time
local cjson           = require("cjson.safe")
local llm_state       = require("kong.llm.state")

local kong          = kong
local ngx           = ngx
local floor         = math.floor
local ngx_re_gmatch = ngx.re.gmatch
local ngx_re_match  = ngx.re.match
local lower         = string.lower
local time          = ngx.time
local fmt           = string.format
local max           = math.max

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

local _STREAM_CHAT_WRAPPER = {
  choices = {
    {
      finish_reason = nil,
      index = 0,
      logprobs = cjson.null,
      message = {
        role = "assistant",
        content = nil,
      },
    }
  },
  id = nil,
  model = nil,
  object = "chat.completion",
  usage = {
    completion_tokens = 0,
    prompt_tokens = 0,
    total_tokens = 0,
  },
}

local SEMANTIC_CACHE_NAMESPACE_PREFIX = "kong_semantic_cache:"

-- [[ LINKED TEST -> 01-unit_spec.lua.["test error analytics output"] ]]
local function send_stats_error(conf, cache_status)
  local aip_conf = llm_state.get_ai_proxy_conf()
  if not aip_conf then
    return
  end

  local response_stats = {
    usage = {
      prompt_tokens = 0,
      completion_tokens = 0,
      total_tokens = 0,
    },
    cache = {
      vector_db = conf.vectordb.driver,
      embeddings_provider = conf.embeddings.driver,
      embeddings_model = conf.embeddings.model,
      cache_status = cache_status,
    }
  }

  ai_shared.post_request(aip_conf, response_stats)
end

-- Helper function to log warnings and return a 400 response
local function bad_request(conf, err, msg)
  if err then 
    kong.log.warn("" .. err)
  end

  send_stats_error(conf, "failed")
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

-- Parses Cache-Control header directives
local function parse_directive_header(h)
  if not h then
    return {}
  end

  if type(h) == "table" then
    local i = 1
    local n = {}
    for key, val in pairs(h) do
      n[i] = fmt("%s=%s", key, val)
      i = i + 1
    end

    h = table.concat(n, ",")
  end

  local t = {}
  local res = {}
  local iter = ngx_re_gmatch(h, "([^,]+)", "oj")
  local m = iter()

  while m do
    -- parse the cache-control directives like: max-age=0
    local _, err = ngx_re_match(m[0], [[^\s*([^=]+)(?:=(.+))?]], "oj", nil, res)
    if err then
      kong.log.err("issue when parsing directive headers " .. err)
    end

    -- Store the directive token as a numeric value if it looks like a number;
    -- otherwise, store the string value. For directives without token, set the key to true.
    t[lower(res[1])] = tonumber(res[2]) or res[2] or true

    m = iter()
  end

  return t
end

-- Retrieves request Cache-Control directives
local function req_cc()
  return parse_directive_header(ngx.var.http_cache_control)
end

-- Retrieves response Cache-Control directives
local function res_cc()
  return parse_directive_header(ngx.var.sent_http_cache_control)
end

-- Calculates resource Time-To-Live (TTL) based on Cache-Control headers
local function resource_ttl(res_cc)
  local max_age = res_cc and (res_cc["s-maxage"] or res_cc["max-age"])

  if not max_age then
    local expires = ngx.var.sent_http_expires

    if type(expires) == "table" then
      expires = expires[#expires]
    end

    local exp_time = parse_http_time(tostring(expires))
    if exp_time then
      max_age = exp_time - time()
    end
  end

  return max_age and max(max_age, 0) or 0
end

-- Checks if the response is cacheable based on Cache-Control directives
local function cacheable_response(conf, cc)
  if conf.cache_control and (cc["private"] or cc["no-store"] or cc["no-cache"]) then
    return false
  end

  if conf.cache_control and resource_ttl(cc) <= 0 then
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

  for i = countback, 1, -1 do
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

local function send_stats(conf, cache_response, cache_status, start_time, embeddings_latency)
  -- only send the stats if an ai-proxy or ai-proxy-advanced plugin is executed
  local aip_conf = llm_state.get_ai_proxy_conf()
  if not aip_conf then
    return
  end

  local response_stats = deep_copy(cache_response)

  -- update timer for latency calculation
  ngx.update_time()

  response_stats.cache = {
    fetch_latency = math.floor((ngx.now() - start_time) * 1000),
    vector_db = conf.vectordb.driver,
    cache_status = cache_status,
  }

  if embeddings_latency then
    response_stats.cache.embeddings_latency = math.floor(embeddings_latency * 1000)
    response_stats.cache.embeddings_provider = conf.embeddings.driver
    response_stats.cache.embeddings_model = conf.embeddings.model
  end

  ai_shared.post_request(aip_conf, response_stats)
end

local function send_response(conf, cache_response, stream_mode, start_time, embeddings_latency, metadata)
  if not cache_response then
    return
  end

  cache_response = cjson.decode(cache_response)

  local cc = req_cc()

  local ttl = conf.storage_ttl or
                conf.cache_control and resource_ttl(cc) or
                conf.cache_ttl

  local cache_age = cache_response.ttl and (ttl - cache_response.ttl) or 0
  local max_age = conf.cache_ttl - cache_age

  if max_age <= 0 then
    llm_state.set_semantic_cache_hit(false)
    kong.log.debug("Semantic cache: refresh")
    local cache_status = "refresh"
    kong.response.set_header("X-Cache-Status", cache_status)
    send_stats(conf, cache_response, cache_status, start_time, embeddings_latency)
    return
  end

  kong.log.debug("Semantic cache: hit")
  local cache_status = "Hit"

  llm_state.set_semantic_cache_hit(true)

  kong.response.set_header("X-Cache-Status", cache_status)
  kong.response.set_header("Age", floor(cache_age))
  if metadata.key then kong.response.set_header("X-Cache-Key", metadata.key) end
  if metadata.ttl then kong.response.set_header("X-Cache-Ttl", metadata.ttl) end

  send_stats(conf, cache_response, cache_status, start_time, embeddings_latency)

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
    ngx.exit(200)
  else
    kong.service.request.enable_buffering()
    cache_response.id = metadata.key
    return kong.response.exit(200, cache_response, { ["Content-Type"] = "application/json; charset=utf-8" })
  end
end

-- Access phase for semantic caching
function AISemanticCaching:access(conf)
  local start_time = ngx.now()

  local cc = req_cc()

  if not cacheable_request(conf, cc) then
    local cache_status = "Bypass"
    kong.response.set_header("X-Cache-Status", cache_status)
    send_stats_error(conf, cache_status)
    return
  end

  local namespace = SEMANTIC_CACHE_NAMESPACE_PREFIX .. conf.__plugin_id

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

  if not validate_incoming(kong.ctx.shared.ai_proxy_original_request) then
    -- Plugin is enabled by accident or non-AI request
    return bad_request(conf, err, "request format is not valid - check for Content-Type or JSON-completeness")
  end

  local stream_mode = kong.ctx.shared.ai_proxy_original_request.stream

  local formatted_chat = format_chat(kong.ctx.shared.ai_proxy_original_request.messages,
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
      send_response(conf, cache_response, stream_mode, start_time, nil, metadata_out)
    end
    metadata_out.refresh_key = cache_key
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
  local embeddings, err = embeddings_driver:generate(formatted_chat)

  if embeddings and (#embeddings ~= conf.vectordb.dimensions) then
    return bad_request(conf, "Embedding dimensions do not match the configured vector database. Embeddings were " ..
      #embeddings .. " dimensions, but the vector database is configured for " ..
      conf.vectordb.dimensions .. " dimensions.", "Embedding dimensions do not match the configured vector database")
  end

  if err then
    if conf.stop_on_failure then
      -- Exit the request early
      llm_state.set_semantic_cache_hit(true)
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

  local cache_response, err = vectordb_driver:search(embeddings, conf.vectordb.default_threshold, metadata_out)

  if err then
    if conf.stop_on_failure then
      -- Exit the request early
      llm_state.set_semantic_cache_hit(true)
      return bad_request(conf, err, "Failed to query '" .. conf.vectordb.driver .. "' for cached response")
    else
      -- Continue regardless of error, but break from the plugin
      kong.log.warn("Failed to query '" .. conf.vectordb.driver .. "' for cached response: ", err, ", plugin config is set to continue on failure")
      return
    end
  end

  -- exit and send response
  send_response(conf, cache_response, stream_mode, start_time, embeddings_latency, metadata_out)

  -- Miss caching
  kong.log.debug("Semantic cache: miss")
  local cache_status = "Miss"
  send_stats_error(conf, cache_status)
  kong.response.set_header("X-Cache-Status", cache_status)
  llm_state.set_semantic_cache_hit(false)
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
    local body
    local content_type = kong.service.response.get_header("Content-Type")

    if content_type then
      local raw_type = split(content_type, ";")[1]

      if raw_type == "application/json" then
        body = llm_state.get_parsed_response()
      elseif raw_type == "text/event-stream" then
        body = kong.ctx.shared.ai_stream_full_text

        local cache_wrapper = deep_copy(_STREAM_CHAT_WRAPPER)
        cache_wrapper.choices[1].message.content = body
        cache_wrapper.model = kong.ctx.shared.ai_response_model
        cache_wrapper.choices[1].finish_reason = kong.ctx.shared.ai_stream_finish_reason

        body = cjson.encode(cache_wrapper)
      end
    else
      kong.log.warn("response is missing content-type header, it will not be cached")
      return
    end

    local embeddings = kong.ctx.plugin.semantic_cache_embeddings
    local cache_key = kong.ctx.plugin.semantic_cache_key
    local storage_ttl = conf.storage_ttl or
                  conf.cache_control and resource_ttl(cc) or
                  conf.cache_ttl
    local namespace = SEMANTIC_CACHE_NAMESPACE_PREFIX .. conf.__plugin_id

    ngx.timer.at(0, function(premature, conf, embeddings, body, cache_key, storage_ttl)
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
  AISemanticCaching._send_stats_error = send_stats_error
  AISemanticCaching._send_stats = send_stats
  AISemanticCaching._validate_incoming = validate_incoming
  AISemanticCaching._resource_ttl = resource_ttl
  AISemanticCaching._format_chat = format_chat
  AISemanticCaching._set_ngx = function(new_ngx)
    ngx = new_ngx
  end
  AISemanticCaching._set_ai_shared = function(new_ai_shared)
    ai_shared = new_ai_shared
  end
end


return AISemanticCaching
