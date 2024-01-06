local _M = {}

-- imports
local cjson = require("cjson.safe")
local http = require("resty.http")
--

local log_entry_keys = {
  REQUEST_BODY = "ai.payload.request",
  RESPONSE_BODY = "ai.payload.response",

  INPUT_TOKENS = "ai.usage.input_tokens",
  OUTPUT_TOKENS = "ai.usage.output_tokens",
  TOTAL_TOKENS = "ai.usage.total_tokens",
  PROCESSING_TIME = "ai.usage.processing_time",

  REQUEST_MODEL = "ai.meta.request_model",
  RESPONSE_MODEL = "ai.meta.response_model",
  PROVIDER_NAME = "ai.meta.provider_name",
}

local request_log_compatible = {
  "llm/v1/chat",
  "llm/v1/completions",
}

_M.upstream_url_format = {
  openai = "https://api.openai.com:443",
  anthropic = "https://api.anthropic.com:443",
  cohere = "https://api.cohere.com:443",
  azure = "https://%s.openai.azure.com:443",
}

_M.operation_map = {
  openai = {
    ["llm/v1/completions"] = {
      path = "/v1/completions",
      method = "POST",
    },
    ["llm/v1/chat"] = {
      path = "/v1/chat/completions",
      method = "POST",
    },
  },
  anthropic = {
    ["llm/v1/completions"] = {
      path = "/v1/complete",
      method = "POST",
    },
    ["llm/v1/chat"] = {
      path = "/v1/complete",
      method = "POST",
    },
  },
  cohere = {
    ["llm/v1/completions"] = {
      path = "/v1/generate",
      method = "POST",
    },
    ["llm/v1/chat"] = {
      path = "/v1/chat",
      method = "POST",
    },
  },
  -- Azure target models also go in the URL
  azure = {
    ["llm/v1/completions"] = {
      path = "/openai/deployments/%s/completions",
      method = "POST",
    },
    ["llm/v1/chat"] = {
      path = "/openai/deployments/%s/completions",
      method = "POST",
    },
  },
}

_M.clear_response_headers = {
  shared = {
    "Content-Length",
  },
  openai = {
    "Set-Cookie",
  },
  azure = {
    "Set-Cookie",
  },
  mistral = {
    "Set-Cookie",
  },
}

function _M.pre_request(conf, request_table)
  -- process form/json body auth information
  local auth_param_name = conf.auth.param_name
  local auth_param_value = conf.auth.param_value
  local auth_param_location = conf.auth.param_location
  
  if auth_param_name and auth_param_value and auth_param_location == "body" then
    request_table[auth_param_name] = auth_param_value
  end

  -- if enabled AND request type is compatible, capture the input for analytics
  if conf.logging.log_payloads then
    kong.log.set_serialize_value(log_entry_keys.REQUEST_BODY, kong.request.get_raw_body())
  end

  return true, nil
end

function _M.post_request(conf, response_string)
  if conf.logging.log_payloads then
    kong.log.set_serialize_value(log_entry_keys.RESPONSE_BODY, response_string)
  end

  -- analytics and logging
  if conf.logging.log_statistics then
    local response_object, err = cjson.decode(response_string)
    if err then
      return "failed to decode response from JSON"
    end

    -- this captures the openai-format usage stats from the transformed response body
    if response_object.usage then
      if response_object.usage.prompt_tokens then
        kong.log.set_serialize_value(
          log_entry_keys.INPUT_TOKENS,
          response_object.usage.prompt_tokens
        )
      end
      if response_object.usage.completion_tokens then
        kong.log.set_serialize_value(
          log_entry_keys.OUTPUT_TOKENS,
          response_object.usage.completion_tokens
        )
      end
      if response_object.usage.total_tokens then
        kong.log.set_serialize_value(
          log_entry_keys.TOTAL_TOKENS,
          response_object.usage.total_tokens
        )
      end
    end
  end

  return nil
end

function _M.http_request(url, body, method, headers, http_opts)
  local httpc = http.new()

  if http_opts.http_timeout then
    httpc:set_timeout(http_opts.http_timeout)
  end

  if http_opts.proxy_opts then
    httpc:set_proxy_options(http_opts.proxy_opts)
  end

  local res, err = httpc:request_uri(
    url,
    {
      method = method,
      body = body,
      headers = headers,
    })
  if not res then
    return nil, "request failed: " .. err
  end

  return res, nil
end

return _M
