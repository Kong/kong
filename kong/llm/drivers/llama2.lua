local _M = {}

-- imports
local cjson = require("cjson.safe")
local split = require("pl.stringx").split
local fmt = string.format
local ai_shared = require("kong.llm.drivers.shared")
local openai_driver = require("kong.llm.drivers.openai")
local socket_url = require "socket.url"
local string_gsub = string.gsub
--

-- globals
local DRIVER_NAME = "llama2"
--

-- parser built from model docs reference:
-- https://huggingface.co/blog/llama2#how-to-prompt-llama-2
local function messages_to_inst(messages)
  local buf = require("string.buffer").new()
  buf:reset()

  for i, v in ipairs(messages) do
    if i == 1 then
      -- first, make the initial prompt
        -- <s>[INST] <<SYS>>
        -- {{ system_prompt }}
        -- <</SYS>>
      buf:putf("<s>[INST] <<SYS>> %s <</SYS>>", v.content)

    elseif i == 2 then
      -- now make the initial user question
        -- {{ user_msg_1 }} [/INST]
      buf:put(fmt(" %s [/INST]", v.content))

    else
      -- continue the chat
      if v.role == "system" then
        -- {{ model_answer_1 }} </s>
        buf:put(fmt(" %s </s>", v.content))

      elseif v.role == "user" then
        buf:put(fmt(" <s>[INST] %s [/INST]", v.content))

      end

    end
  end

  return buf:get(), nil
end

local function from_raw(response_string, model_info, route_type)
  local response_table, err = cjson.decode(response_string)
  if err then
    return nil, "failed to decode llama2 response"
  end

  if (not response_table) or (not response_table.data) or (#response_table.data > 1) then
    return nil, "cannot parse response from llama2 endpoint"

  elseif (not response_table.data[1].generated_text) then
    return nil, "response data is empty from llama2 endpoint"

  end

  local split_response = split(response_table.data[1].generated_text, "[/INST]")
  if not split_response or #split_response < 1 then
    return nil, "response did not contain a system reply"
  end

  local response_object

  -- good
  if route_type == "llm/v1/chat" then
    response_object = {
      choices = {
        [1] = {
          message = {
            content = string_gsub(split_response[#split_response], '^%s*(.-)%s*$', '%1'),
            role = "assistant",
          },
          index = 0,
        }
      },
      object = "chat.completion",
    }

  elseif route_type == "llm/v1/completions" then
    response_object = {
      choices = {
        [1] = {
          index = 0,
          text = string_gsub(split_response[#split_response], '^%s*(.-)%s*$', '%1'),
        }
      },
      object = "text_completion",
    }

  end

  -- stash analytics for later
  if response_table.usage then response_object.usage = response_table.usage end

  return cjson.encode(response_object)
end

local function to_raw(request_table, model)
  local messages = {}
  messages.parameters = {}
  messages.parameters.max_new_tokens = model.options and model.options.max_tokens
  messages.parameters.top_p = model.options and model.options.top_p or 1.0
  messages.parameters.top_k = model.options and model.options.top_k or 40
  messages.parameters.temperature = model.options and model.options.temperature
  
  if request_table.prompt and request_table.messages then
    return kong.response.exit(400, "cannot run raw 'prompt' and chat history 'messages' requests at the same time - refer to schema")

  elseif request_table.messages then
    messages.inputs = messages_to_inst(request_table.messages)

  elseif request_table.prompt then
    messages.inputs = fmt("<s> [INST] <<SYS>> You are a helpful assistant. <<SYS>> %s [/INST]", request_table.prompt)

  end

  return messages, "application/json", nil
end

-- transformer mappings
local transformers_from = {
  ["llm/v1/chat/raw"] = from_raw,
  ["llm/v1/completions/raw"] = from_raw,
  ["llm/v1/chat/ollama"] = ai_shared.from_ollama,
  ["llm/v1/completions/ollama"] = ai_shared.from_ollama,
}

local transformers_to = {
  ["llm/v1/chat/raw"] = to_raw,
  ["llm/v1/completions/raw"] = to_raw,
  ["llm/v1/chat/ollama"] = ai_shared.to_ollama,
  ["llm/v1/completions/ollama"] = ai_shared.to_ollama,
}
--

function _M.from_format(response_string, model_info, route_type)
  -- MUST return a string, to set as the response body
  ngx.log(ngx.DEBUG, "converting from ", model_info.provider, "://", route_type, " type to kong")

  if model_info.options.llama2_format == "openai" then
    return openai_driver.from_format(response_string, model_info, route_type)
  end

  local transformer_type = fmt("%s/%s", route_type, model_info.options.llama2_format)
  if not transformers_from[transformer_type] then
    return nil, fmt("no transformer available from format %s://%s", model_info.provider, transformer_type)
  end
  
  local ok, response_string, err = pcall(
    transformers_from[transformer_type],
    response_string,
    model_info,
    route_type
  )
  if not ok or err then
    return nil, fmt("transformation failed from type %s://%s: %s", model_info.provider, route_type, err or "unexpected_error")
  end

  return response_string, nil
end

function _M.to_format(request_table, model_info, route_type)
  ngx.log(ngx.DEBUG, "converting from kong type to ", model_info.provider, "://", route_type)

  if model_info.options.llama2_format == "openai" then
    return openai_driver.to_format(request_table, model_info, route_type)
  end

  -- dynamically call the correct transformer
  local ok, response_object, content_type, err = pcall(
    transformers_to[fmt("%s/%s", route_type, model_info.options.llama2_format)],
    request_table,
    model_info
  )
  if err or (not ok) then
    return nil, nil, fmt("error transforming to %s://%s/%s", model_info.provider, route_type, model_info.options.llama2_format)
  end

  return response_object, content_type, nil
end

function _M.subrequest(body, conf, http_opts, return_res_table)
  -- use shared/standard subrequest routine
  local body_string, err

  if type(body) == "table" then
    body_string, err = cjson.encode(body)
    if err then
      return nil, nil, "failed to parse body to json: " .. err
    end
  elseif type(body) == "string" then
    body_string = body
  else
    return nil, nil, "body must be table or string"
  end

  local url = conf.model.options.upstream_url

  local method = "POST"

  local headers = {
    ["Accept"] = "application/json",
    ["Content-Type"] = "application/json"
  }

  if conf.auth and conf.auth.header_name then
    headers[conf.auth.header_name] = conf.auth.header_value
  end

  local res, err = ai_shared.http_request(url, body_string, method, headers, http_opts)
  if err then
    return nil, nil, "request to ai service failed: " .. err
  end

  if return_res_table then
    return res, res.status, nil
  else
    -- At this point, the entire request / response is complete and the connection
    -- will be closed or back on the connection pool.
    local status = res.status
    local body   = res.body

    if status > 299 then
      return body, res.status, "status code " .. status
    end

    return body, res.status, nil
  end
end

function _M.header_filter_hooks(body)
  -- nothing to parse in header_filter phase
end

function _M.post_request(conf)
  if ai_shared.clear_response_headers[DRIVER_NAME] then
    for i, v in ipairs(ai_shared.clear_response_headers[DRIVER_NAME]) do
      kong.response.clear_header(v)
    end
  end
end

function _M.pre_request(conf, body)
  -- check for user trying to bring own model
  if body and body.model then
    return false, "cannot use own model for this instance"
  end

  return true, nil
end

-- returns err or nil
function _M.configure_request(conf)
  local parsed_url = socket_url.parse(conf.model.options.upstream_url)

  kong.service.request.set_path(parsed_url.path)
  kong.service.request.set_scheme(parsed_url.scheme)
  kong.service.set_target(parsed_url.host, tonumber(parsed_url.port))

  local auth_header_name = conf.auth and conf.auth.header_name
  local auth_header_value = conf.auth and conf.auth.header_value
  local auth_param_name = conf.auth and conf.auth.param_name
  local auth_param_value = conf.auth and conf.auth.param_value
  local auth_param_location = conf.auth and conf.auth.param_location

  if auth_header_name and auth_header_value then
    kong.service.request.set_header(auth_header_name, auth_header_value)
  end

  if auth_param_name and auth_param_value and auth_param_location == "query" then
    local query_table = kong.request.get_query()
    query_table[auth_param_name] = auth_param_value
    kong.service.request.set_query(query_table)
  end

  -- if auth_param_location is "form", it will have already been set in a pre-request hook
  return true, nil
end


return _M
