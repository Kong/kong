-- imports
local typedefs  = require("kong.db.schema.typedefs")
local fmt       = string.format
local cjson     = require("cjson.safe")
local re_match  = ngx.re.match
local buf       = require("string.buffer")
local lower     = string.lower
local meta      = require "kong.meta"
local ai_shared = require("kong.llm.drivers.shared")
local strip     = require("kong.tools.utils").strip
--

local _M = {}

local auth_schema = {
  type = "record",
  required = false,
  fields = {
    { header_name = {
        type = "string",
        description = "If AI model requires authentication via Authorization or API key header, specify its name here.",
        required = false,
        referenceable = true }},
    { header_value = {
        type = "string",
        description = "Specify the full auth header value for 'header_name', for example 'Bearer key' or just 'key'.",
        required = false,
        encrypted = true,  -- [[ ee declaration ]]
        referenceable = true }},
    { param_name = {
        type = "string",
        description = "If AI model requires authentication via query parameter, specify its name here.",
        required = false,
        referenceable = true }},
    { param_value = {
        type = "string",
        description = "Specify the full parameter value for 'param_name'.",
        required = false,
        encrypted = true,  -- [[ ee declaration ]]
        referenceable = true }},
    { param_location = {
        type = "string",
        description = "Specify whether the 'param_name' and 'param_value' options go in a query string, or the POST form/JSON body.",
        required = false,
        one_of = { "query", "body" } }},
  }
}

local model_options_schema = {
  description = "Key/value settings for the model",
  type = "record",
  required = false,
  fields = {
    { response_streaming = {
        type = "string",
        description = "Whether to 'optionally allow', 'deny', or 'always' (force) the streaming of answers via WebSocket.",
        required = true,
        default = "allow",
        one_of = { "allow", "deny", "always" } }},
    { max_tokens = {
        type = "integer",
        description = "Defines the max_tokens, if using chat or completion models.",
        required = false,
        default = 256 }},
    { temperature = {
        type = "number",
        description = "Defines the matching temperature, if using chat or completion models.",
        required = false,
        between = { 0.0, 5.0 },
        default = 1.0 }},
    { top_p = {
        type = "number",
        description = "Defines the top-p probability mass, if supported.",
        required = false,
        between = { 0, 1 },
        default = 1.0 }},
    { top_k = {
        type = "integer",
        description = "Defines the top-k most likely tokens, if supported.",
        required = false,
        between = { 0, 500 },
        default = 0 }},
    { anthropic_version = {
        type = "string",
        description = "Defines the schema/API version, if using Anthropic provider.",
        required = false }},
    { azure_instance = {
        type = "string",
        description = "Instance name for Azure OpenAI hosted models.",
        required = false }},
    { azure_api_version = {
        type = "string",
        description = "'api-version' for Azure OpenAI instances.",
        required = false,
        default = "2023-05-15" }},
    { azure_deployment_id = {
        type = "string",
        description = "Deployment ID for Azure OpenAI instances.",
        required = false }},
    { llama2_format = {
        type = "string",
        description = "If using llama2 provider, select the upstream message format.",
        required = false,
        one_of = { "raw", "openai", "ollama" }}},
    { mistral_format = {
        type = "string",
        description = "If using mistral provider, select the upstream message format.",
        required = false,
        one_of = { "openai", "ollama" }}},
    { upstream_url = typedefs.url {
        description = "Manually specify or override the full URL to the AI operation endpoints, "
                   .. "when calling (self-)hosted models, or for running via a private endpoint.",
        required = false }},
  }
}

local model_schema = {
  type = "record",
  required = true,
  fields = {
    { provider = { 
        type = "string", description = "AI provider request format - Kong translates "
                                    .. "requests to and from the specified backend compatible formats.",
        required = true,
        one_of = { "openai", "azure", "anthropic", "cohere", "mistral", "llama2" }}},
    { name = {
        type = "string",
        description = "Model name to execute.",
        required = false }},
    { options = model_options_schema },
  }
}

local logging_schema = {
  type = "record",
  required = true,
  fields = {
    { log_statistics = {
        type = "boolean",
        description = "If enabled and supported by the driver, "
                   .. "will add model usage and token metrics into the Kong log plugin(s) output.",
                   required = true,
                   default = false }},
    { log_payloads = {
        type = "boolean", 
        description = "If enabled, will log the request and response body into the Kong log plugin(s) output.",
        required = true, default = false }},
  }
}

local UNSUPPORTED_LOG_STATISTICS = {
  ["llm/v1/completions"] = { ["anthropic"] = true },
}

_M.config_schema = {
  type = "record",
  fields = {
    { route_type = {
        type = "string",
        description = "The model's operation implementation, for this provider.",
        required = true,
        one_of = { "llm/v1/chat", "llm/v1/completions" } }},
    { auth = auth_schema },
    { model = model_schema },
    { logging = logging_schema },
  },
  entity_checks = {
    -- these three checks run in a chain, to ensure that all auth params for each respective "set" are specified
    { conditional_at_least_one_of = { if_field = "model.provider",
                                      if_match = { one_of = { "openai", "azure", "anthropic", "cohere" } },
                                      then_at_least_one_of = { "auth.header_name", "auth.param_name" },
                                      then_err = "must set one of %s, and its respective options, when provider is not self-hosted" }},

    { mutually_required = { "auth.header_name", "auth.header_value" }, },
    { mutually_required = { "auth.param_name", "auth.param_value", "auth.param_location" }, },

    { conditional_at_least_one_of = { if_field = "model.provider",
                                      if_match = { one_of = { "llama2" } },
                                      then_at_least_one_of = { "model.options.llama2_format" },
                                      then_err = "must set %s for llama2 provider" }},

    { conditional_at_least_one_of = { if_field = "model.provider",
                                      if_match = { one_of = { "mistral" } },
                                      then_at_least_one_of = { "model.options.mistral_format" },
                                      then_err = "must set %s for mistral provider" }},

    { conditional_at_least_one_of = { if_field = "model.provider",
                                      if_match = {  },
                                      then_at_least_one_of = { "model.name" },
                                      then_err = "Must set a model name. Refer to https://docs.konghq.com/hub/kong-inc/ai-proxy/ " ..
                                                 "for supported models." }},

    { conditional_at_least_one_of = { if_field = "model.provider",
                                      if_match = { one_of = { "anthropic" } },
                                      then_at_least_one_of = { "model.options.anthropic_version" },
                                      then_err = "must set %s for anthropic provider" }},

    { conditional_at_least_one_of = { if_field = "model.provider",
                                      if_match = { one_of = { "azure" } },
                                      then_at_least_one_of = { "model.options.azure_instance" },
                                      then_err = "must set %s for azure provider" }},

    { conditional_at_least_one_of = { if_field = "model.provider",
                                      if_match = { one_of = { "azure" } },
                                      then_at_least_one_of = { "model.options.azure_api_version" },
                                      then_err = "must set %s for azure provider" }},

    { conditional_at_least_one_of = { if_field = "model.provider",
                                      if_match = { one_of = { "azure" } },
                                      then_at_least_one_of = { "model.options.azure_deployment_id" },
                                      then_err = "must set %s for azure provider" }},

    { conditional_at_least_one_of = { if_field = "model.provider",
                                      if_match = { one_of = { "mistral", "llama2" } },
                                      then_at_least_one_of = { "model.options.upstream_url" },
                                      then_err = "must set %s for self-hosted providers/models" }},

    {
      custom_entity_check = {
        field_sources = { "route_type", "model", "logging" },
        fn = function(entity)
          -- print(cjson.encode(entity))
          if entity.logging.log_statistics and UNSUPPORTED_LOG_STATISTICS[entity.route_type]
            and UNSUPPORTED_LOG_STATISTICS[entity.route_type][entity.model.provider] then
              return nil, fmt("%s does not support statistics when route_type is %s",
                               entity.model.provider, entity.route_type)

          else
            return true
          end
        end,
      }
    },
  },
}

local streaming_skip_headers = {
  ["connection"]        = true,
  ["content-type"]      = true,
  ["keep-alive"]        = true,
  ["set-cookie"]        = true,
  ["transfer-encoding"] = true,
  ["via"]               = true,
}

local formats_compatible = {
  ["llm/v1/chat"] = {
    ["llm/v1/chat"] = true,
  },
  ["llm/v1/completions"] = {
    ["llm/v1/completions"] = true,
  },
}

local function bad_request(msg)
  ngx.log(ngx.WARN, msg)
  ngx.status = 400
  ngx.header["Content-Type"] = "application/json"
  ngx.say(cjson.encode({ error = { message = msg } }))
end

local function internal_server_error(msg)
  ngx.log(ngx.ERR, msg)
  ngx.status = 500
  ngx.header["Content-Type"] = "application/json"
  ngx.say(cjson.encode({ error = { message = msg } }))
end

local function identify_request(request)
  -- primitive request format determination
  local formats = {}

  if request.messages
    and type(request.messages) == "table"
    and #request.messages > 0
      then
        table.insert(formats, "llm/v1/chat")
  end
  
  if request.prompt
    and type(request.prompt) == "string"
      then
        table.insert(formats, "llm/v1/completions")
  end

  if #formats > 1 then
    return nil, "request matches multiple LLM request formats"
  elseif not formats_compatible[formats[1]] then
    return nil, "request format not recognised"
  else
    return formats[1]
  end
end

local function get_token_text(event_t)
  -- chat
  return
    event_t and
    event_t.choices and
    #event_t.choices > 0 and
    event_t.choices[1].delta and
    event_t.choices[1].delta.content

    or

  -- completions
    event_t and
    event_t.choices and
    #event_t.choices > 0 and
    event_t.choices[1].text

    or ""
end

-- Function to count the number of words in a string
local function count_words(str)
  local count = 0
  for word in str:gmatch("%S+") do
      count = count + 1
  end
  return count
end

-- Function to count the number of words or tokens based on the content type
local function count_prompt(content, tokens_factor)
  local count = 0

  if type(content) == "string" then
    count = count_words(content) * tokens_factor
  elseif type(content) == "table" then
    for _, item in ipairs(content) do
      if type(item) == "string" then
        count = count + (count_words(item) * tokens_factor)
      elseif type(item) == "number" then
        count = count + 1
      elseif type(item) == "table" then
        for _2, item2 in ipairs(item) do
          if type(item2) == "number" then
            count = count + 1
          else
            return nil, "Invalid request format"
          end
        end
      else
          return nil, "Invalid request format"
      end
    end
  else 
    return nil, "Invalid request format"
  end
  return count
end

function _M:calculate_cost(query_body, tokens_models, tokens_factor)
  local query_cost = 0
  local err

  -- Check if max_tokens is provided in the request body
  local max_tokens = query_body.max_tokens
  
  if not max_tokens then
    if query_body.model and tokens_models then
      max_tokens = tonumber(tokens_models[query_body.model])
    end
  end

  if not max_tokens then
    return nil, "No max_tokens in query and no key found in the plugin config for model: " .. query_body.model
  end

  if query_body.messages then
    -- Calculate the cost based on the content type
    for _, message in ipairs(query_body.messages) do
        query_cost = query_cost + (count_words(message.content) * tokens_factor)
    end
  elseif query_body.prompt then
    -- Calculate the cost based on the content type
    query_cost, err = count_prompt(query_body.prompt, tokens_factor)
    if err then
        return nil, err
    end
  else
    return nil, "No messages or prompt in query"
  end

  -- Round the total cost quantified
  query_cost = math.floor(query_cost + 0.5)

  return query_cost
end

function _M.is_compatible(request, route_type)
  local format, err = identify_request(request)
  if err then 
    return nil, err
  end

  if formats_compatible[format][route_type] then
    return true
  end

  return false, fmt("[%s] message format is not compatible with [%s] route type", format, route_type)
end

function _M:handle_streaming_request(body)
  -- convert it to the specified driver format
  local request, _, err = self.driver.to_format(body, self.conf.model, self.conf.route_type)
  if err then
    return internal_server_error(err)
  end

  -- run the shared logging/analytics/auth function
  ai_shared.pre_request(self.conf, request)

  local prompt_tokens = 0
  local err
  if not ai_shared.streaming_has_token_counts[self.conf.model.provider] then
    -- Estimate the cost using KONG CX's counter implementation
    prompt_tokens, err = self:calculate_cost(request, {}, 1.8)
    if err then
      return internal_server_error("unable to estimate request token cost: " .. err)
    end
  end

  -- send it to the ai service
  local res, _, err, httpc = self.driver.subrequest(request, self.conf, self.http_opts, true)
  if err then
    return internal_server_error("failed to connect to " .. self.conf.model.provider .. " for streaming: " .. err)
  end
  if res.status ~= 200 then
    err = "bad status code whilst opening streaming to " .. self.conf.model.provider .. ": " .. res.status
    ngx.log(ngx.WARN, err)
    return bad_request(err)
  end

  -- get a big enough buffered ready to make sure we rip the entire chunk(s) each time
  local reader = res.body_reader
  local buffer_size = 35536
  local events

  -- we create a fake "kong response" table to pass to the telemetry handler later
  local telemetry_fake_table = {
    response = buf:new(),
    usage = {
      prompt_tokens = prompt_tokens,
      completion_tokens = 0,
      total_tokens = 0,
    },
  }

  ngx.status = 200
  ngx.header["Content-Type"] = "text/event-stream"
  ngx.header["Via"] = meta._SERVER_TOKENS

  for k, v in pairs(res.headers) do
    if not streaming_skip_headers[lower(k)] then
      ngx.header[k] = v
    end
  end

  -- server-sent events should ALWAYS be chunk encoded.
  -- if they aren't then... we just won't support them.
  repeat
    -- receive next chunk
    local buffer, err = reader(buffer_size)
    if err then
        ngx.log(ngx.ERR, "failed to read chunk of streaming buffer, ", err)
        break
    elseif not buffer then
      break
    end

    -- we need to rip each message from this chunk
    events = {}
    for s in buffer:gmatch("[^\r\n]+") do
      table.insert(events, s)
    end

    local metadata
    local route_type = "stream/" .. self.conf.route_type

    -- then parse each into the standard inference format
    for i, event in ipairs(events) do
      local event_t
      local token_t

      -- some LLMs do a final reply with token counts, and such
      -- so we will stash them if supported
      local formatted, err, this_metadata = self.driver.from_format(event, self.conf.model, route_type)
      if err then
        return internal_server_error(err)
      end

      metadata = this_metadata or metadata

      -- handle event telemetry
      if self.conf.logging.log_statistics then

        if not ai_shared.streaming_has_token_counts[self.conf.model.provider] then
          event_t = cjson.decode(formatted)
          token_t = get_token_text(event_t)

          -- incredibly loose estimate based on https://help.openai.com/en/articles/4936856-what-are-tokens-and-how-to-count-them
          -- but this is all we can do until OpenAI fixes this...
          --
          -- essentially, every 4 characters is a token, with minimum of 1 per event
          telemetry_fake_table.usage.completion_tokens =
              telemetry_fake_table.usage.completion_tokens + math.ceil(#strip(token_t) / 4)

        elseif metadata then
          telemetry_fake_table.usage.completion_tokens = metadata.completion_tokens
          telemetry_fake_table.usage.prompt_tokens = metadata.prompt_tokens
        end

      end

      -- then stream to the client
      if formatted then  -- only stream relevant frames back to the user
        if self.conf.logging.log_payloads then
          -- append the "choice" to the buffer, for logging later. this actually works!
          if not event_t then
            event_t, err = cjson.decode(formatted)
          end

          if err then
            return internal_server_error("something wrong with decoding a specific token")
          end

          if not token_t then
            token_t = get_token_text(event_t)
          end

          telemetry_fake_table.response:put(token_t)
        end

        -- construct, transmit, and flush the frame
        ngx.print("data: ", formatted, "\n\n")
        ngx.flush(true)
      end
    end

  until not buffer

  local ok, err = httpc:set_keepalive()
  if not ok then
    -- continue even if keepalive gets killed
    ngx.log(ngx.WARN, "setting keepalive failed: ", err)
  end

  -- process telemetry
  telemetry_fake_table.response = telemetry_fake_table.response:tostring()

  telemetry_fake_table.usage.total_tokens = telemetry_fake_table.usage.completion_tokens +
                                telemetry_fake_table.usage.prompt_tokens

  ai_shared.post_request(self.conf, telemetry_fake_table)
end

function _M:ai_introspect_body(request, system_prompt, http_opts, response_regex_match)
  local err, _

  -- set up the request
  local ai_request = {
    messages = {
      [1] = {
        role = "system",
        content = system_prompt,
      },
      [2] = {
        role = "user",
        content = request,
      }
    },
    stream = false,
  }

  -- convert it to the specified driver format
  ai_request, _, err = self.driver.to_format(ai_request, self.conf.model, "llm/v1/chat")
  if err then
    return nil, err
  end

  -- run the shared logging/analytics/auth function
  ai_shared.pre_request(self.conf, ai_request)

  -- send it to the ai service
  local ai_response, _, err = self.driver.subrequest(ai_request, self.conf, http_opts, false)
  if err then
    return nil, "failed to introspect request with AI service: " .. err
  end

  -- parse and convert the response
  local ai_response, _, err = self.driver.from_format(ai_response, self.conf.model, self.conf.route_type)
  if err then
    return nil, "failed to convert AI response to Kong format: " .. err
  end

  -- run the shared logging/analytics function
  ai_shared.post_request(self.conf, ai_response)

  local ai_response, err = cjson.decode(ai_response)
  if err then
    return nil, "failed to convert AI response to JSON: " .. err
  end

  local new_request_body = ai_response.choices
                       and #ai_response.choices > 0
                       and ai_response.choices[1]
                       and ai_response.choices[1].message
                       and ai_response.choices[1].message.content
  if not new_request_body then
    return nil, "no 'choices' in upstream AI service response"
  end

  -- if specified, extract the first regex match from the AI response
  -- this is useful for AI models that pad with assistant text, even when
  -- we ask them NOT to.
  if response_regex_match then
    local matches, err = re_match(new_request_body, response_regex_match, "ijom")
    if err then
      return nil, "failed regex matching ai response: " .. err
    end

    if matches then
      new_request_body = matches[0]  -- this array DOES start at 0, for some reason

    else
      return nil, "AI response did not match specified regular expression"

    end
  end

  return new_request_body
end

function _M:parse_json_instructions(in_body)
  local err
  if type(in_body) == "string" then
    in_body, err = cjson.decode(in_body)
    if err then
      return nil, nil, nil, err
    end
  end

  if type(in_body) ~= "table" then
    return nil, nil, nil, "input not table or string"
  end

  return 
    in_body.headers,
    in_body.body or in_body,
    in_body.status or 200
end

function _M:new(conf, http_opts)
  local o = {}
  setmetatable(o, self)
  self.__index = self

  self.conf = conf or {}
  self.http_opts = http_opts or {}

  local driver = fmt("kong.llm.drivers.%s", conf
                                        and conf.model
                                        and conf.model.provider
                                         or "NONE_SET")

  self.driver = require(driver)

  if not self.driver then
    return nil, fmt("could not instantiate %s package", driver)
  end

  return o
end

return _M
