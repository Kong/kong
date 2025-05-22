local cjson = require("cjson.safe")
local fmt = string.format

local _GeminiAdapter = {}

_GeminiAdapter.role_map = {
  ["human"] = "user",
  ["model"] = "assistant",
  ["function"] = "tool",
}

-- Creates a new GeminiAdapter.
-- @param o (table or nil) The object to create the adapter from.
function _GeminiAdapter:new(o)
  o = o or {}
  setmetatable(o, self)

  self.__index = self

  -- The format ID for the adapter.
  self.FORMAT_ID = "gemini"

  -- The LLM provider drivers compatible with the adapter.
  self.PROVIDERS_COMPATIBLE = {
    ["gemini"] = true,
  }

  return o
end

-- Determines if the adapter is compatible with a provider.
-- @param provider (string) The provider to check compatibility with.
-- @return (boolean) True if compatible, false otherwise.
function _GeminiAdapter:is_compatible(provider)
  return self.PROVIDERS_COMPATIBLE[provider]
end

-- Extracts metadata from a Gemini response body and returns a table of fields to add to analytics.
-- @param response_body (string) The Gemini response body.
-- @return res (table) The Kong AI Gateway response metadata object.
function _GeminiAdapter:extract_metadata(response_body)
  if response_body then
    local err
    response_body, err = cjson.decode(response_body)
    if err then
      return nil, err
    end

    if response_body.usageMetadata then
      return {
        prompt_tokens = response_body.usageMetadata.promptTokenCount or 0,
        completion_tokens = response_body.usageMetadata.candidatesTokenCount or 0,
      }
    end

  end

  return {
    prompt_tokens = 0,
    completion_tokens = 0,
  }
end

-- Extracts the response model version from a Gemini response table.
-- @param response_body (table) The Gemini response table.
-- @return model_version (string) The model version.
function _GeminiAdapter:extract_response_model(response_body)
  if response_body then
    local err
    response_body, err = cjson.decode(response_body)
    if err then
      return nil, err
    end

    return response_body.modelVersion
  end

  return nil
end

-- Converts a Gemini part to an OpenAI part.
-- @param part (table) The Gemini part.
-- @return new_part (table) The OpenAI part.
function _GeminiAdapter:gemini_part_to_openai_part(part)
  if part.text then
    return {
      ["type"] = "text",
      ["text"] = part.text
    }

  elseif part.inline_data then
    local mimetype = part.inline_data.mime_type
    local data = part.inline_data.data

    return {
      ["type"] = "image_url",
      ["image_url"] = {
        ["url"] = fmt("data:%s;base64,%s", mimetype, data)
      }
    }

  elseif part.file_data then
    -- TODO handle this better
    -- OpenAI only supports image_url for the chat endpoints right now
    -- but Gemini supports audio, video, and others.
    --
    -- We'll have to just assumed it's image_url and wait for OpenAI
    -- support later.
    --
    -- This WON'T break the parser or the native request, it will just
    -- look weird in the logs.
    local file_uri = part.file_data.file_uri

    return {
      ["type"] = "image_url",
      ["image_url"] = {
        ["url"] = file_uri
      }
    }

  elseif part.functionCall then
    return {
      ["type"] = "function",
      ["function"] = {
        ["name"] = part.functionCall.name,
        ["id"] = part.functionCall.name,
        ["arguments"] = cjson.encode(part.functionCall.args),
      },
    }

  end
end

-- Converts a Gemini message to a Kong message.
-- @param msg (table) The Gemini message.
-- @return new_msg (table) The Kong message.
function _GeminiAdapter:gemini_msg_to_openai_msg(msg)
  local new_msg = {}

  if msg.role and type(msg.role) == "string" then
    new_msg.role = _GeminiAdapter.role_map[msg.role] or msg.role
  end

  if msg.parts
     and type(msg.parts) == "table" then

    new_msg.content = nil
    new_msg.tool_calls = nil

    -- handle parts-by-key, and array-of-parts, differently
    if #msg.parts > 0 then
      for _, v in ipairs(msg.parts) do
        local part = self:gemini_part_to_openai_part(v)
        
        -- this is a special case
        if v.functionCall then
          new_msg.tool_calls = new_msg.tool_calls or {}
          table.insert(new_msg.tool_calls, part)

        elseif v.function_response then
          new_msg.content = v.function_response.response and v.function_response.response.content

        else
          new_msg.content = new_msg.content or {}
          table.insert(new_msg.content, part)
        end
      end

    elseif next(msg.parts) then
        -- this is a special case
        if msg.parts.functionCall then
          new_msg.tool_calls = new_msg.tool_calls or {}
          table.insert(new_msg.tool_calls, msg.parts.functionCall)

        elseif msg.parts.function_response then
          -- special case, replaces the whole message
          new_msg.content = cjson.encode(msg.parts.function_response.response and msg.parts.function_response.response.content)

      else
        new_msg.content = new_msg.content or {}
        table.insert(new_msg.content, self:gemini_part_to_openai_part(msg.parts))
      end

    end

  end

  return new_msg
end


-- Converts a Gemini contents table to a Kong messages table.
-- @param response_table (table) The Gemini contents table.
-- @return res (table) The Kong messages table.
function _GeminiAdapter:extract_messages(contents, system_instruction)
  local messages

  for _, msg in ipairs(contents) do
    messages = messages or {}
    table.insert(messages, self:gemini_msg_to_openai_msg(msg))
  end

  -- handle the system prompt differently for Gemini
  if system_instruction then
    local system_text
    if #system_instruction.parts > 0 then
      system_text = system_instruction.parts[1].text
    elseif next(system_instruction.parts) then
      system_text = system_instruction.parts.text
    end

    if system_text then
      table.insert(messages, 1, { role = "system", content = { { type = "text", text = system_text } } })
    end
  end

  return messages
end


-- Updates the native Gemini request table with the given configuration.
-- @param native_request_t (table) The native Gemini request table.
-- @param conf_m (table) The configuration table.
function _GeminiAdapter:update_inference_parameters(native_request_t, conf_m)
  -- for performance, we only need to decode and encode the body
  -- if something actually changes
  native_request_t.generationConfig = native_request_t.generationConfig or {}

  native_request_t.generationConfig.temperature = conf_m.model.options and conf_m.model.options.temperature or native_request_t.generationConfig.temperature
  native_request_t.generationConfig.maxOutputTokens = conf_m.model.options and conf_m.model.options.max_tokens or native_request_t.generationConfig.maxOutputTokens
  native_request_t.generationConfig.topP = conf_m.model.options and conf_m.model.options.top_p or native_request_t.generationConfig.topP
  native_request_t.generationConfig.topK = conf_m.model.options and conf_m.model.options.top_k or native_request_t.generationConfig.topK
end


-- Extracts metadata from a Gemini request table and returns a table of fields to add to converted Kong request.
-- @param request_table (table) The Gemini generationConfig from the request.
-- @return req (table) The Kong AI Gateway response metadata object.
function _GeminiAdapter:extract_inference_parameters(generationConfig)
  if generationConfig then
    local openai_parameters = {}

    openai_parameters.temperature = generationConfig.temperature
    openai_parameters.max_tokens = generationConfig.maxOutputTokens
    openai_parameters.top_p = generationConfig.topP
    openai_parameters.top_k = generationConfig.topK
    openai_parameters.stop = generationConfig.stopSequences

    return openai_parameters
  end

end

-- Extracts the model name and whether it is streaming, from the incoming coordinates.
-- @param path (string) The request path.
-- @param uri_captures (table) The URI captures.
-- @return model_name (string) The model name.
-- @return stream (boolean) Whether the response should stream.
function _GeminiAdapter:extract_model_and_stream(path, uri_captures)
  -- try named URI captures first
  local model_name = uri_captures.named and uri_captures.named.model
  local operation = uri_captures.named and uri_captures.named.operation

  -- otherwise try raw parsing the path,
  --  in case the user has set this up incorrectly

  -- TODO: also consider upstream_url?
  if (not model_name) or (not operation) then
    local t_model_name, t_operation = path:match("/models/([^:]+):([^/]+)$")

    model_name = t_model_name or model_name
    operation = t_operation or operation
  end

  return model_name, (operation == "streamGenerateContent" and true) or false
end

-- Extracts tools from a Gemini request table and returns a table of fields to add to converted Kong request.
-- @param request_table (table) The Gemini tools from the request.
-- @return req (table) The Kong AI Gateway response metadata object.
function _GeminiAdapter:extract_tools(tools)
  local openai_tools = {}

  for _, tool in ipairs(tools[1].function_declarations) do
    local new_tool = {
      ["type"] = "function",
      ["function"] = tool,
    }

    -- TODO any customisation here, looks like there is none
    --      it's just a standard jsonschema snippet

    table.insert(openai_tools, new_tool)
  end

  return openai_tools
end


-- Converts a Gemini request table to a Kong request table.
-- @param request_table (table) The Gemini request table.
-- @return req (table) The Kong request table.
function _GeminiAdapter:to_kong_req(gemini_table, kong)
  local openai_table = {}

  -- try to capture the model from the request path
  -- otherwise we'll use the model name from the plugin config
  -- otherwise we'll fail the request
  openai_table.model, openai_table.stream = self:extract_model_and_stream(kong.request.get_path(), kong.request.get_uri_captures())

  if gemini_table.contents
       and type(gemini_table.contents) == "table" then
    
    if #gemini_table.contents > 0 then
      -- convert messages
      openai_table.messages = self:extract_messages(gemini_table.contents, gemini_table.system_instruction)
    
    elseif next(gemini_table.contents) then
      openai_table.messages = {
        self:gemini_msg_to_openai_msg(gemini_table.contents)
      }
    end

  end

  -- convert tuning parameters
  if gemini_table.generationConfig then
    for k, v in pairs(self:extract_inference_parameters(gemini_table.generationConfig)) do
      openai_table[k] = v
    end
  end
  
  -- finally handle tool definitions
  if gemini_table.tools
       and type(gemini_table.tools) == "table"
       and #gemini_table.tools > 0
       and type(gemini_table.tools[1]) == "table"
       and gemini_table.tools[1].function_declarations
       and #gemini_table.tools[1].function_declarations > 0 then

    openai_table.tools = self:extract_tools(gemini_table.tools)
  end

  return openai_table
end


-- for unit tests
if _G.TEST then
  _GeminiAdapter._set_kong = function(this_kong)
    _G.kong = this_kong
  end
  _GeminiAdapter._get_kong = function()
    return kong
  end
end


return _GeminiAdapter
