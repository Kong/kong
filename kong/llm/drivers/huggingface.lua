local _M = {}

-- imports
local cjson = require("cjson.safe")
local fmt = string.format
local ai_shared = require("kong.llm.drivers.shared")
local socket_url = require("socket.url")
local ai_plugin_ctx = require("kong.llm.plugin.ctx")
--

local DRIVER_NAME = "huggingface"

function _M.pre_request(conf, body)
  return true, nil
end

local function from_huggingface(response_string, model_info, route_type)
  local response_table, err = cjson.decode(response_string)
  if not response_table then
    ngx.log(ngx.ERR, "Failed to decode JSON response from HuggingFace API: ", err)
    return nil, "Failed to decode response"
  end

  if response_table.error or response_table.message then
    local error_msg = response_table.error or response_table.message
    ngx.log(ngx.ERR, "Error from HuggingFace API: ", error_msg)
    return nil, "API error: " .. error_msg
  end

  local transformed_response = {
    model = model_info.name,
    object = response_table.object or route_type,
    choices = {},
    usage = {},
  }

  -- Chat reports usage, generation does not
  transformed_response.usage = response_table.usage or {}

  response_table.generated_text = response_table[1] and response_table[1].generated_text or nil
  if response_table.generated_text then
    table.insert(transformed_response.choices, {
      message = { content = response_table.generated_text },
      index = 0,
      finish_reason = "complete",
    })
  elseif response_table.choices then
    for i, choice in ipairs(response_table.choices) do
      local content = choice.message and choice.message.content or ""
      table.insert(transformed_response.choices, {
        message = { content = content },
        index = i - 1,
        finish_reason = "complete",
      })
    end
  else
    ngx.log(ngx.ERR, "Unexpected response format from Hugging Face API")
    return nil, "Invalid response format"
  end

  local result_string, err = cjson.encode(transformed_response)
  if not result_string then
    ngx.log(ngx.ERR, "Failed to encode transformed response: ", err)
    return nil, "Failed to encode response"
  end
  return result_string, nil
end

local function set_huggingface_options(model_info)
  local use_cache = false
  local wait_for_model = false

  if model_info and model_info.options and model_info.options.huggingface then
    use_cache = model_info.options.huggingface.use_cache or false
    wait_for_model = model_info.options.huggingface.wait_for_model or false
  end

  return {
    use_cache = use_cache,
    wait_for_model = wait_for_model,
  }
end

local function set_default_parameters(request_table)
  local parameters = request_table.parameters or {}
  if parameters.top_k == nil then
    parameters.top_k = request_table.top_k
  end
  if parameters.top_p == nil then
    parameters.top_p = request_table.top_p
  end
  if parameters.temperature == nil then
    parameters.temperature = request_table.temperature
  end
  if parameters.max_tokens == nil then
    if request_table.messages then
      -- conversational model use the max_lenght param
      -- https://huggingface.co/docs/api-inference/en/detailed_parameters?code=curl#conversational-task
      parameters.max_lenght = request_table.max_tokens
    else
      parameters.max_new_tokens = request_table.max_tokens
    end
  end
  request_table.top_k = nil
  request_table.top_p = nil
  request_table.temperature = nil
  request_table.max_tokens = nil

  return parameters
end

local function to_huggingface(task, request_table, model_info)
  local parameters = set_default_parameters(request_table)
  local options = set_huggingface_options(model_info)
  if task == "llm/v1/completions" then
    request_table.inputs = request_table.prompt
    request_table.prompt = nil
  end
  request_table.options = options
  request_table.parameters = parameters
  request_table.model = model_info.name or request_table.model

  return request_table, "application/json", nil
end

local function safe_access(tbl, ...)
  local value = tbl
  for _, key in ipairs({ ... }) do
    value = value and value[key]
    if not value then
      return nil
    end
  end
  return value
end

local function handle_huggingface_stream(event_t, model_info, route_type)
  -- discard empty frames, it should either be a random new line, or comment
  if (not event_t.data) or (#event_t.data < 1) then
    return
  end
  local event, err = cjson.decode(event_t.data)

  if err then
    ngx.log(ngx.WARN, "failed to decode stream event frame from Hugging Face: ", err)
    return nil, "failed to decode stream event frame from Hugging Face", nil
  end

  local new_event
  if route_type == "stream/llm/v1/chat" then
    local content = safe_access(event, "choices", 1, "delta", "content") or ""
    new_event = {
      choices = {
        [1] = {
          delta = {
            content = content,
            role = "assistant",
          },
          index = 0,
        },
      },
      model = event.model or model_info.name,
      object = "chat.completion.chunk",
    }
  else
    local text = safe_access(event, "token", "text") or ""
    new_event = {
      choices = {
        [1] = {
          text = text,
          index = 0,
        },
      },
      model = model_info.name,
      object = "text_completion",
    }
  end
  return cjson.encode(new_event), nil, nil
end

local transformers_from = {
  ["llm/v1/chat"] = from_huggingface,
  ["llm/v1/completions"] = from_huggingface,
  ["stream/llm/v1/chat"] = handle_huggingface_stream,
  ["stream/llm/v1/completions"] = handle_huggingface_stream,
}

function _M.from_format(response_string, model_info, route_type)
  ngx.log(ngx.DEBUG, "converting from ", model_info.provider, "://", route_type, " type to kong")

  -- MUST return a string, set as the response body
  if not transformers_from[route_type] then
    return nil, fmt("no transformer available from format %s://%s", model_info.provider, route_type)
  end

  local ok, response_string, err, metadata =
    pcall(transformers_from[route_type], response_string, model_info, route_type)
  if not ok or err then
    return nil,
      fmt("transformation failed from type %s://%s: %s", model_info.provider, route_type, err or "unexpected_error")
  end

  return response_string, nil, metadata
end

local transformers_to = {
  ["llm/v1/chat"] = to_huggingface,
  ["llm/v1/completions"] = to_huggingface,
}

function _M.to_format(request_table, model_info, route_type)
  if not transformers_to[route_type] then
    return nil, nil, fmt("no transformer for %s://%s", model_info.provider, route_type)
  end

  request_table = ai_shared.merge_config_defaults(request_table, model_info.options, model_info.route_type)

  local ok, response_object, content_type, err =
    pcall(transformers_to[route_type], route_type, request_table, model_info)
  if err or not ok then
    return nil, nil, fmt("error transforming to %s://%s", model_info.provider, route_type)
  end

  return response_object, content_type, nil
end

local function build_url(base_url, route_type)
  return (route_type == "llm/v1/completions") and base_url or (base_url .. "/v1/chat/completions")
end

local function huggingface_endpoint(conf, model)
  local parsed_url

  local base_url
  if model.options and model.options.upstream_url then
    base_url = model.options.upstream_url
  elseif model.name then
    base_url = fmt(ai_shared.upstream_url_format[DRIVER_NAME], model.name)
  else
    return nil
  end

  local url = build_url(base_url, conf.route_type)
  parsed_url = socket_url.parse(url)

  return parsed_url
end

function _M.configure_request(conf)
  local model = ai_plugin_ctx.get_request_model_table_inuse()
  if not model or type(model) ~= "table" or model.provider ~= DRIVER_NAME then
    return nil, "invalid model parameter"
  end

  local parsed_url = huggingface_endpoint(conf, model)
  if not parsed_url then
    return kong.response.exit(400, "Could not parse the Hugging Face model endponit")
  end
  if parsed_url.path then
    kong.service.request.set_path(parsed_url.path)
  end
  kong.service.request.set_scheme(parsed_url.scheme)
  kong.service.set_target(parsed_url.host, tonumber(parsed_url.port) or 443)

  local auth_header_name = conf.auth and conf.auth.header_name
  local auth_header_value = conf.auth and conf.auth.header_value

  if auth_header_name and auth_header_value then
    kong.service.request.set_header(auth_header_name, auth_header_value)
  end
  return true, nil
end

function _M.post_request(conf)
  -- Clear any response headers if needed
  if ai_shared.clear_response_headers[DRIVER_NAME] then
    for i, v in ipairs(ai_shared.clear_response_headers[DRIVER_NAME]) do
      kong.response.clear_header(v)
    end
  end
end

function _M.subrequest(body, conf, http_opts, return_res_table)
  -- Encode the request body as JSON
  local body_string, err = cjson.encode(body)
  if not body_string then
    return nil, nil, "Failed to encode body to JSON: " .. (err or "unknown error")
  end

  -- Construct the Hugging Face API URL
  local url = huggingface_endpoint(conf)
  if not url then
    return nil, nil, "Could not parse the Hugging Face model endpoint"
  end
  local url_string = url.scheme .. "://" .. url.host .. (url.path or "")

  local headers = {
    ["Accept"] = "application/json",
    ["Content-Type"] = "application/json",
  }

  if conf.auth and conf.auth.header_name then
    headers[conf.auth.header_name] = conf.auth.header_value
  end

  local method = "POST"

  local res, err, httpc = ai_shared.http_request(url_string, body_string, method, headers, http_opts, return_res_table)

  -- Handle the response
  if not res then
    return nil, nil, "Request to Hugging Face API failed: " .. (err or "unknown error")
  end

  -- Check if the response should be returned as a table
  if return_res_table then
    return {
      status = res.status,
      headers = res.headers,
      body = res.body,
    },
      res.status,
      nil,
      httpc
  else
    if res.status >= 200 and res.status < 300 then
      return res.body, res.status, nil
    else
      return res.body, res.status, "Hugging Face API returned status " .. res.status
    end
  end
end

return _M
