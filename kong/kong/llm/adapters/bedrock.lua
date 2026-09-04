local cjson = require("cjson.safe")
local fmt = string.format

local _BedrockAdapter = {}

_BedrockAdapter.role_map = {
  ["user"] = "user",
  ["assistant"] = "assistant",
  ["tool"] = "tool",
}

-- Creates a new BedrockAdapter.
-- @param o (table or nil) The object to create the adapter from.
function _BedrockAdapter:new(o)
  o = o or {}
  setmetatable(o, self)

  self.__index = self

  -- The format ID for the adapter.
  self.FORMAT_ID = "bedrock"

  -- The LLM provider drivers compatible with the adapter.
  self.PROVIDERS_COMPATIBLE = {
    ["bedrock"] = true,
  }

  return o
end

-- Determines if the adapter is compatible with a provider.
-- @param provider (string) The provider to check compatibility with.
-- @return (boolean) True if compatible, false otherwise.
function _BedrockAdapter:is_compatible(provider)
  return self.PROVIDERS_COMPATIBLE[provider]
end


-- Extracts metadata from a Bedrock response body and returns a table of fields to add to analytics.
-- @param response_body (string) The Bedrock response body.
-- @return res (table) The Kong AI Gateway response metadata object.
function _BedrockAdapter:extract_metadata(response_body)
  if response_body then
    local err
    response_body, err = cjson.decode(response_body)
    if err then
      return nil, err
    end

    if response_body.usage then
      return {
        prompt_tokens = response_body.usage.inputTokens or 0,
        completion_tokens = response_body.usage.outputTokens or 0,
      }
    end

  end

  return {
    prompt_tokens = 0,
    completion_tokens = 0,
  }
end

-- Extracts the response model version from a Bedrock response table.
-- @param response_body (table) The Bedrock response table.
-- @return nil (nil) Bedrock doesn't return a model revision.
function _BedrockAdapter:extract_response_model(response_body)
  -- Bedrock doesn't return this.
  -- Kong will use the incoming model name in the analytics.
  return nil
end

-- Converts a Bedrock part to a Kong part.
-- @param part (table) The Bedrock part.
-- @return new_part (table) The Kong part.
function _BedrockAdapter:bedrock_part_to_openai_part(part)
  if part.text then
    return {
      ["type"] = "text",
      ["text"] = part.text
    }

  elseif part.image then
    local mimetype = part.image.format
    local data = part.image.source and part.image.source.bytes

    return {
      ["type"] = "image_url",
      ["image_url"] = {
        ["url"] = fmt("data:image/%s;base64,%s", mimetype, data)
      }
    }

  elseif part.toolUse then
    return {
      ["id"] = part.toolUse.toolUseId,
      ["function"] = {
        ["name"] = part.toolUse.name,
        ["arguments"] = cjson.encode(part.toolUse.input or {}),
      },
      ["type"] = "function",
    }

  elseif part.toolResult then
    return {
      ["tool_call_id"] = part.toolResult.toolUseId,
      ["content"] = cjson.encode(#part.toolResult.content > 0 and part.toolResult.content[1].json or part.toolResult.content),
    }

  else
    return nil
  end

end

-- Converts a Bedrock message to a Kong message.
-- @param msg (table) The Bedrock message.
-- @return new_msg (table) The Kong message.
function _BedrockAdapter:bedrock_msg_to_openai_msg(msg)
  local new_msg = {}

  if msg.role and type(msg.role) == "string" then
    new_msg.role = _BedrockAdapter.role_map[msg.role] or msg.role
  end

  if msg.content
     and type(msg.content) == "table" then

    new_msg.content = nil
    new_msg.tool_calls = nil

    if #msg.content > 0 then
      for _, v in ipairs(msg.content) do
        local part = self:bedrock_part_to_openai_part(v)

        if v.toolUse then
          new_msg.tool_calls = new_msg.tool_calls or {}
          table.insert(new_msg.tool_calls, part)
        
        -- special formatter, replaces the whole message
        elseif v.toolResult then
          new_msg.role = "tool"
          new_msg.content = part.content
          new_msg.tool_call_id = part.tool_call_id

        else
          new_msg.content = new_msg.content or {}
          table.insert(new_msg.content, part)
        end
      end

    end

  end

  return new_msg
end


-- Converts a Bedrock messages table to a Kong messages table.
-- @param response_table (table) The Bedrock messages table.
-- @return res (table) The Kong messages table.
function _BedrockAdapter:extract_messages(messages, system)
  local openai_messages

  for _, msg in ipairs(messages) do
    openai_messages = openai_messages or {}
    table.insert(openai_messages, self:bedrock_msg_to_openai_msg(msg))
  end

  -- handle the system prompt differently for Bedrock
  if system then
    local system_instruction = system
                               and type(system) == "table"
                               and #system > 0
                               and system[1].text

    if system_instruction then
      table.insert(openai_messages, 1, { role = "system", content = { { type = "text", text = system_instruction } } })
    end
  end

  return openai_messages
end


-- Updates the native Bedrock request table with the given configuration.
-- @param native_request_t (table) The native Bedrock request table.
-- @param conf_m (table) The configuration table.
function _BedrockAdapter:update_inference_parameters(native_request_t, conf_m)
  -- for performance, we only need to decode and encode the body
  -- if something actually changes
  native_request_t.generationConfig = native_request_t.generationConfig or {}

  native_request_t.generationConfig.temperature = conf_m.model.options and conf_m.model.options.temperature or native_request_t.generationConfig.temperature
  native_request_t.generationConfig.maxOutputTokens = conf_m.model.options and conf_m.model.options.max_tokens or native_request_t.generationConfig.maxOutputTokens
  native_request_t.generationConfig.topP = conf_m.model.options and conf_m.model.options.top_p or native_request_t.generationConfig.topP
  native_request_t.generationConfig.topK = conf_m.model.options and conf_m.model.options.top_k or native_request_t.generationConfig.topK
end


-- Extracts metadata from a Bedrock request table and returns a table of fields to add to converted Kong request.
-- @param request_table (table) The Bedrock inferenceConfig from the request.
-- @return req (table) The Kong AI Gateway response metadata object.
function _BedrockAdapter:extract_inference_parameters(inferenceConfig)
  if inferenceConfig then
    local openai_parameters = {}

    openai_parameters.temperature = inferenceConfig.temperature
    openai_parameters.max_tokens = inferenceConfig.maxTokens
    openai_parameters.top_p = inferenceConfig.topP
    openai_parameters.stop = inferenceConfig.stopSequences

    return openai_parameters
  end

end

-- Extracts the model name and whether it is streaming, from the incoming coordinates.
-- @param path (string) The request path.
-- @param uri_captures (table) The URI captures.
-- @return model_name (string) The model name.
-- @return stream (boolean) Whether the response should stream.
function _BedrockAdapter:extract_model_and_stream(path, uri_captures)
  -- try named URI captures first
  local model_name = uri_captures.named and uri_captures.named.model
  local operation = uri_captures.named and uri_captures.named.operation

  -- otherwise try raw parsing the path,
  --  in case the user has set this up incorrectly
  -- TODO: also consider upstream_url?
  if (not model_name) or (not operation) then
    local t_model_name, t_operation = path:match("/model/([^/]+)/([^/]+)$")

    model_name = t_model_name or model_name
    operation = t_operation or operation
  end

  -- XTODO remember to re-encode the model name when you **SIGN THE REQUEST**
  return ngx.unescape_uri(model_name), (operation == "converse-stream" and true) or false
end

-- Extracts tools from a Bedrock request table and returns a table of fields to add to converted Kong request.
-- @param request_table (table) The Bedrock tools from the request.
-- @return req (table) The Kong AI Gateway response metadata object.
function _BedrockAdapter:extract_tools(tools)
  local openai_tools = {}

  for _, tool in ipairs(tools) do
    if tool.toolSpec and tool.toolSpec then
      local new_tool = {
        ["type"] = "function",
        ["function"] = {
          ["name"] = tool.toolSpec.name,
          ["description"] = tool.toolSpec.description,
          ["parameters"] = tool.toolSpec.inputSchema and tool.toolSpec.inputSchema.json or nil,
        },
      }

      -- TODO any customisation here, looks like there is none
      --      it's just a standard jsonschema snippet

      table.insert(openai_tools, new_tool)
    end
  end

  return openai_tools
end


-- Converts a Bedrock request table to a Kong request table.
-- @param request_table (table) The Bedrock request table.
-- @return req (table) The Kong request table.
function _BedrockAdapter:to_kong_req(bedrock_table, kong)
  local openai_table = {}

  -- try to capture the model from the request path
  -- otherwise we'll use the model name from the plugin config
  -- otherwise we'll fail the request
  openai_table.model, openai_table.stream = self:extract_model_and_stream(kong.request.get_path(), kong.request.get_uri_captures())

  if bedrock_table.messages
       and type(bedrock_table.messages) == "table"
       and #bedrock_table.messages > 0 then

      -- convert messages
      openai_table.messages = self:extract_messages(bedrock_table.messages, bedrock_table.system)
  end

  -- convert tuning parameters
  if bedrock_table.inferenceConfig then
    for k, v in pairs(self:extract_inference_parameters(bedrock_table.inferenceConfig)) do
      openai_table[k] = v
    end
  end

  -- finally handle tool definitions
  if bedrock_table.toolConfig
       and type(bedrock_table.toolConfig) == "table"
       and bedrock_table.toolConfig.tools
       and type(bedrock_table.toolConfig.tools) == "table"
       and #bedrock_table.toolConfig.tools > 0 then

    openai_table.tools = self:extract_tools(bedrock_table.toolConfig.tools)
  end

  return openai_table
end


-- for unit tests
if _G.TEST then
  _BedrockAdapter._set_kong = function(this_kong)
    _G.kong = this_kong
  end
  _BedrockAdapter._get_kong = function()
    return kong
  end
end


return _BedrockAdapter
