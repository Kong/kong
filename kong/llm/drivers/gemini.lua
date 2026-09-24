local _M = {}

-- imports
local cjson = require("kong.tools.cjson")
local fmt = string.format
local anthropic = require("kong.llm.drivers.anthropic")
local openai = require("kong.llm.drivers.openai")
local ai_shared = require("kong.llm.drivers.shared")
local socket_url = require("socket.url")
local string_gsub = string.gsub
local buffer = require("string.buffer")
local table_insert = table.insert
local table_concat = table.concat
local ai_plugin_ctx = require("kong.llm.plugin.ctx")
local ai_plugin_base = require("kong.llm.plugin.base")
local pl_string = require "pl.stringx"
local model_garden_openai_chat_path = "/v1/projects/%s/locations/%s/endpoints/%s/chat/completions"
local uuid = require("kong.tools.uuid").uuid
--

-- globals
local DRIVER_NAME = "gemini"
local get_global_ctx, set_global_ctx = ai_plugin_ctx.get_global_accessors(DRIVER_NAME)
--

local _OPENAI_ROLE_MAPPING = {
  ["system"] = "system",
  ["user"] = "user",
  ["assistant"] = "model",
  ["model"] = "assistant",
  ["tool"] = "user",
}

local _OPENAI_STOP_REASON_MAPPING = {
  ["MAX_TOKENS"] = "length",
  ["STOP"] = "stop",
}

local _OPENAI_STRUCTURED_OUTPUT_TYPE_MAP = {
  ["json_schema"] = "application/json",
}

local function to_gemini_generation_config(request_table)
  return {
    ["maxOutputTokens"] = request_table.max_tokens,
    ["stopSequences"] = request_table.stop,
    ["temperature"] = request_table.temperature,
    ["topK"] = request_table.top_k,
    ["topP"] = request_table.top_p,
  }
end

local function is_content_safety_failure(content)
  return content
          and content.candidates
          and #content.candidates > 0
          and content.candidates[1].finishReason
          and content.candidates[1].finishReason == "SAFETY"
end

local function is_response_content(content)
  return content
        and content.candidates
        and #content.candidates > 0
        and content.candidates[1].content
        and content.candidates[1].content.parts
        and #content.candidates[1].content.parts > 0
        and content.candidates[1].content.parts[1].text
end

local function is_tool_content(content)
  return content
        and content.candidates
        and #content.candidates > 0
        and content.candidates[1].content
        and content.candidates[1].content.parts
        and #content.candidates[1].content.parts > 0
        and content.candidates[1].content.parts[1].functionCall
end

local function has_finish_reason(event)
  return event
         and event.candidates
         and #event.candidates > 0
         and event.candidates[1].finishReason
         or nil
end

local function extract_structured_content(request_table)
  -- bounds check EVERYTHING first
  if not request_table
    or not request_table.response_format
    or type(request_table.response_format.type) ~= "string"
    or type(request_table.response_format.json_schema) ~= "table"
    or type(request_table.response_format.json_schema.schema) ~= "table"
  then
    return nil
  end

  -- transform
  ---- no transformations for OpenAI-to-Gemini

  -- return
  return _OPENAI_STRUCTURED_OUTPUT_TYPE_MAP[request_table.response_format.type], request_table.response_format.json_schema.schema
end


local function get_model_coordinates(model_name, stream_mode)
  if not model_name then
    return nil, "model_name must be set to get model coordinates"
  end

  -- anthropic
  if model_name:sub(1, 7) == "claude-" then
    return {
      publisher = "anthropic",
      operation = stream_mode and "streamRawPredict" or "rawPredict",
    }

  -- mistral
  elseif model_name:sub(1, 8) == "mistral-" then
    return {
      publisher = "mistral",
      operation = stream_mode and "streamRawPredict" or "rawPredict",
    }

  -- ai21 (jamba)
  elseif model_name:sub(1, 6) == "jamba-" then
    return {
      publisher = "ai21",
      operation = stream_mode and "streamRawPredict" or "rawPredict",
    }

  else
    return {
      publisher = "google",
      operation = stream_mode and "streamGenerateContent" or "generateContent",
    }
  end
end

-- assume 'not vertex mode' if the model options are not set properly
-- the plugin schema will prevent misconfugiration
local function is_vertex_mode(model)
  return model 
         and model.options
         and model.options.gemini
         and model.options.gemini.api_endpoint
         and model.options.gemini.project_id
         and model.options.gemini.location_id
         and true
end

-- this will never be called unless is_vertex_mode(model) above is true
-- so the deep table checks are not needed
local function get_gemini_vertex_url(model, route_type, stream_mode)
  if not model.options or not model.options.gemini then
    return nil, "model.options.gemini.* options must be set for vertex mode"
  end

  local forward_path, err
  local llm_format_adapter = get_global_ctx("llm_format_adapter")
  if llm_format_adapter then
    local _
    forward_path, _, err = llm_format_adapter:get_forwarded_path(model.name, model.options)
    if err then
      ngx.log(ngx.WARN, "failed to get forwarded path from llm_format_adapter: ", err)
      forward_path = nil
    end
  end

  if not forward_path then
    local coordinates, err = get_model_coordinates(model.name, stream_mode)
    if err then
      return nil, err
    end

    if model.options.gemini.endpoint_id and model.options.gemini.endpoint_id ~= ngx.null then
      -- means gcp vertex garden
      forward_path = fmt(model_garden_openai_chat_path,
              model.options.gemini.project_id,
              model.options.gemini.location_id,
              model.options.gemini.endpoint_id)
    else
      forward_path = fmt(ai_shared.operation_map["gemini_vertex"][route_type].path,
              model.options.gemini.project_id,
              model.options.gemini.location_id,
              coordinates.publisher,
              model.name,
              coordinates.operation)
    end


  end

  return fmt(ai_shared.upstream_url_format["gemini_vertex"],
             model.options.gemini.api_endpoint) .. forward_path
end

local function handle_stream_event(event_t, model_info, route_type)
  -- discard empty frames, it should either be a random new line, or comment
  if (not event_t.data) or (#event_t.data < 1) then
    return
  end

  if event_t.data == ai_shared._CONST.SSE_TERMINATOR then
    return ai_shared._CONST.SSE_TERMINATOR, nil, nil
  end

  local event, err = cjson.decode_with_array_mt(event_t.data)
  if err then
    ngx.log(ngx.WARN, "failed to decode stream event frame from gemini: ", err)
    return nil, "failed to decode stream event frame from gemini", nil
  end

  local finish_reason = has_finish_reason(event)  -- may be nil

  if is_response_content(event) then
    local metadata = {}
    metadata.finish_reason = (finish_reason and _OPENAI_STOP_REASON_MAPPING[finish_reason or "STOP"])
    metadata.completion_tokens = event.usageMetadata and event.usageMetadata.candidatesTokenCount or 0
    metadata.prompt_tokens     = event.usageMetadata and event.usageMetadata.promptTokenCount or 0
    metadata.created, err = ai_shared.iso_8601_to_epoch(event.createTime or ai_shared._CONST.UNIX_EPOCH)
    if err then
      ngx.log(ngx.WARN, "failed to convert createTime to epoch: ", err, ", fallback to 1970-01-01T00:00:00Z")
      metadata.created = 0
    end

    metadata.id = event.responseId

    local new_event = {
      model = model_info.name,
      choices = {
        [1] = {
          delta = {
            content = event.candidates[1].content.parts[1].text or "",
            role = "assistant",
          },
          index = 0,
          finish_reason = (finish_reason and _OPENAI_STOP_REASON_MAPPING[finish_reason or "STOP"])
        },
      },
    }

    if get_global_ctx("structured_output_mode")
       and #event.candidates[1].content.parts[1].text > 2
       and event.candidates[1].content.parts[1].text == "[]" then
        -- simulate OpenAI "refusal" where the question/answer doesn't fit the structured output schema
        new_event.choices[1].delta.content = nil
        new_event.choices[1].delta.refusal = "Kong: Vertex refused to answer the question, because it did not fit the structured output schema"
    end

    return cjson.encode(new_event), nil, metadata
  
  elseif is_tool_content(event) then
    local metadata = {}
    metadata.finish_reason     = _OPENAI_STOP_REASON_MAPPING[finish_reason or "STOP"]
    metadata.completion_tokens = event.usageMetadata and event.usageMetadata.candidatesTokenCount or 0
    metadata.prompt_tokens     = event.usageMetadata and event.usageMetadata.promptTokenCount or 0
    metadata.created, err = ai_shared.iso_8601_to_epoch(event.createTime or ai_shared._CONST.UNIX_EPOCH)
    if err then
      ngx.log(ngx.WARN, "failed to convert createTime to epoch: ", err, ", fallback to 1970-01-01T00:00:00Z")
      metadata.created = 0
    end
    metadata.id = event.responseId

    if event.candidates and #event.candidates > 0 then
      local new_event = {
        model = model_info.name,
        choices = {
          [1] = {
            delta = {
              tool_calls = {},
            },
            index = 0,
            finish_reason = finish_reason
          },
        },
      }

      local function_call_responses = event.candidates[1].content.parts

      if function_call_responses and #function_call_responses > 0 then
        for i, v in ipairs(function_call_responses) do
          new_event.choices[1].delta.tool_calls[i] = {
            ['function'] = {
              name = v.functionCall.name,
              arguments = cjson.encode(v.functionCall.args),
            },
            ['type'] = "function",
          }
        end
      end

      return cjson.encode(new_event), nil, metadata
    end
  end
end


local function image_url_to_components(img)
  -- determine the protocol from the first 10 bytes
  if #img < 10 then
    return nil, "image URL is less than 10 bytes, which is not parsable"
  end

  -- capture only 10 bytes for the 'protocol://' to increase performance
  local protocol_parts = pl_string.split(img:sub(1, 6), ":")

  if protocol_parts then
    local protocol = protocol_parts[1]

    -- if the protocol is "data" then we can parse it,
    -- otherwise just send it as-is, because it's probably
    -- as GCP bucket or https link.
    if protocol == "data" then
      local coordinates_outer = pl_string.split(img:sub(#protocol+2), ";")
      local coordinates_inner = pl_string.split(coordinates_outer[2], ",")

      return {
        mimetype = coordinates_outer[1],
        encoding = coordinates_inner[1],
        data = coordinates_inner[2],
      }
    else
      return img
    end
  end

  return nil, "unable to determine the PROTOCOL from the image url"
end

-- expects nil return if part does not match expected format or cannot be transformed
local function openai_part_to_gemini_part(openai_part)
  if not openai_part then
    return nil
  end

  local gemini_part

  if openai_part.type and openai_part.type == "image_url" then
    if not (openai_part.image_url and openai_part.image_url.url) then
      return nil, "message part type is 'image_url' but is missing .image_url.url block"
    end

    local image_components, err = image_url_to_components(openai_part.image_url.url)
    if err then
      return nil, "could not decode OpenAI image-part, " .. err
    end

    if image_components and type(image_components) == "table" then
      gemini_part = {
        inlineData = {
          data = image_components.data,
          mimeType = image_components.mimetype,
        }
      }

    elseif image_components and type(image_components) == "string" then
      gemini_part = {
        fileData = {
          fileUri = image_components,
          mimeType = "image/generic",
        }
      }

    end

  elseif openai_part.type and openai_part.type == "text" then
    if not openai_part.text then
      return nil, "message part type is 'text' but is missing .text block"
    end

    gemini_part = {
      text = openai_part.text,
    }

  else
    return nil, "cannot transform part of type '" .. openai_part.type .. "' to Gemini format"
  end

  return gemini_part
end

local function extract_function_calls(message)
  if message
      and message.tool_calls
      and type(message.tool_calls) == "table"
      and #message.tool_calls > 0
  then
    local function_calls = {}

    for _, tool_call in ipairs(message.tool_calls) do
      if tool_call['type'] == "function" and tool_call['function'] then
        local args, err = cjson.decode(tool_call['function'].arguments)
        if err then
          return nil, "failed to decode function response arguments from assistant's message, not JSON format"
        end

        local gemini_tool_call = {
          functionCall = {
            name = tool_call['function'].name,
            args = args,
          },
        }

        -- Gemini expects function calls to be in the 'parts' array
        table_insert(function_calls, gemini_tool_call)
      end
    end

    return #function_calls > 0 and function_calls or nil

  else
    return nil
  end
end

local function to_tools(tools)
  if not tools or type(tools) ~= "table" then
    return nil
  end

  local out_tools

  for i, tool in ipairs(tools) do
    if tool.type == "function" and tool['function'] then
      out_tools = out_tools or {
        [1] = {
          function_declarations = {}
        }
      }

      out_tools[1].function_declarations[i] = tool['function']
    end
  end

  return out_tools
end

local function openai_toolcontent_to_gemini_toolcontent(content)
  if not content then
    return {
      result = true  -- for now, we'll assume that OpenAI accepts empty result as "WAS EXECUTED"
    }
  end
  
  if type(content) == "string" then
    -- try to decode json
    local decoded_content, _ = cjson.decode(content)
    if decoded_content and type(decoded_content) == "table" then
      return decoded_content
      
    else
      return {
        result = content  -- it's probably a string result on its own, emulate this OpenAI functionality for Gemini
      }
    end
  end
end

local function extract_function_called_name(tool_calls, tool_call_id)
  if not tool_calls 
      or not tool_calls.tool_calls
      or type(tool_calls.tool_calls) ~= "table" or #tool_calls.tool_calls < 1 then
    return nil
  end

  -- Find the tool_call_id from the tool_calls message previous
  if tool_call_id then
    for _, tool_call in ipairs(tool_calls.tool_calls) do
      if tool_call.id == tool_call_id then
        return tool_call['function'] and tool_call['function'].name
      end
    end
  end

  return nil
end

local function openai_toolresult_to_gemini_toolresult(tool_calls_msg, tool_result_message)
  if not tool_result_message then
    return nil, "tool result message is nil"
  end

  local function_called_name = extract_function_called_name(tool_calls_msg, tool_result_message.tool_call_id)
  local tool_result_content = openai_toolcontent_to_gemini_toolcontent(tool_result_message.content)

  if function_called_name and tool_result_content then
    return {
      functionResponse = {
        name = function_called_name,  -- JTODO: get the name from the previous message, link up the IDs
        response = tool_result_content,
      }
    }

  else
      return nil, "tool result message content does not match expected OpenAI format"
  end
end

local function to_gemini_chat_openai(request_table, model_info, route_type)
  local new_r = {}

  if request_table then
    local tool_calls_message_cache

    if request_table.messages and #request_table.messages > 0 then
      local system_prompt

      for i, v in ipairs(request_table.messages) do

        -- for 'system', we just concat them all into one Gemini instruction
        if v.role and v.role == "system" then
          system_prompt = system_prompt or buffer.new()
          system_prompt:put(v.content or "")

        elseif ai_shared.is_tool_result_message(v) then
          -- This will also have "content" as a string but
          -- requires completely different out-of-sequence handling

          -- Is the previous message already a tool result?
          -- Gemini expects all tool results from a previous message to
          -- be in the same 'parts' array in its following reply message.
          if i > 1 and ai_shared.is_tool_result_message(request_table.messages[i-1]) then
            -- append to the previous message's 'parts' array
            local previous_parts = new_r.contents[#new_r.contents].parts or {}

            local this_part, err = openai_toolresult_to_gemini_toolresult(tool_calls_message_cache, v)
            if not this_part then
              if not err then
                err = "tool call result at position " .. i-1 .. " does not match expected OpenAI format"
              end
              return nil, nil, err
            end

            table_insert(previous_parts, this_part)
            new_r.contents[#new_r.contents].parts = previous_parts

          else
            -- This is the start of the function result blocks
            tool_calls_message_cache = request_table.messages[i-1]  -- hold this for next N "tool use" msgs as we iterate
            
            local this_part, err = openai_toolresult_to_gemini_toolresult(tool_calls_message_cache, v)
            if not this_part then
              if not err then
                err = "tool call result at position " .. i-1 .. " does not match expected OpenAI format"
              end
              return nil, nil, err
            end

            table_insert(new_r.contents, {
              role = _OPENAI_ROLE_MAPPING[v.role or "tool"],  -- default to Gemini 'user'
              parts = { this_part },
            })
          end

        else
          local this_parts = {}

          -- for any other role, just construct the chat history as 'parts' type
          new_r.contents = new_r.contents or {}

          if type(v.content) == "string" then
            this_parts = {
              {
                text = v.content,
              },
            }

          elseif type(v.content) == "table" then
            if #v.content > 0 then  -- check it has some kind of array element
              for j, part in ipairs(v.content) do
                local this_part, err = openai_part_to_gemini_part(part)
                
                if not this_part then
                  if not err then
                    err = "message at position " .. i .. ", part at position " .. j .. " does not match expected OpenAI format"
                  end
                  return nil, nil, err
                end

                this_parts[j] = this_part
              end
            else
              return nil, nil, "message at position " .. i .. " does not match expected array format"
            end
          end

          local function_calls, err = extract_function_calls(v)
          if err then
            return nil, nil, "failed to extract function calls from message at position " .. i-1 .. ": " .. err
          end

          if function_calls then
            for _, func_call in ipairs(function_calls) do
              -- Gemini expects function calls to be in the 'parts' array
              table_insert(this_parts, func_call)
            end
          end

          table_insert(new_r.contents, {
            role = _OPENAI_ROLE_MAPPING[v.role or "user"],  -- default to 'user'
            parts = this_parts,
          })
        end

      end

      -- This was only added in Gemini 1.5
      if system_prompt and model_info.name:sub(1, 10) == "gemini-1.0" then
        return nil, nil, "system prompts aren't supported on gemini-1.0 models"

      elseif system_prompt then
        new_r.systemInstruction = {
          parts = {
            {
              text = system_prompt:get(),
            },
          },
        }
      end
    end

    new_r.generationConfig = to_gemini_generation_config(request_table)

    -- convert OpenAI structured output to Gemini, if it is specified
    local response_mime_type, response_schema = extract_structured_content(request_table)
    if response_mime_type and response_schema then
      set_global_ctx("structured_output_mode", true)
      new_r.generationConfig = new_r.generationConfig or {}
      new_r.generationConfig.response_mime_type = response_mime_type
      new_r.generationConfig.response_json_schema = response_schema
    end

    -- handle function calling translation from OpenAI format
    new_r.tools = request_table.tools and to_tools(request_table.tools)
    new_r.tool_config = request_table.tool_config
  end

  return new_r, "application/json", nil
end

local function extract_response_finish_reason(response_candidate)
  if response_candidate
        and response_candidate.content
        and response_candidate.content.parts
        and type(response_candidate.content.parts) == "table"
        and #response_candidate.content.parts > 0
  then
    for _, part in ipairs(response_candidate.content.parts) do
      if part.functionCall then
        return "tool_calls"
      end
    end
  end

  return "stop"
end

local function feedback_to_kong_error(promptFeedback)
  if promptFeedback
      and type(promptFeedback) == "table"
  then
    return {
      error = true,
      message = promptFeedback.blockReasonMessage or cjson.null,
      reason = promptFeedback.blockReason or cjson.null,
    }
  end

  return nil
end

local function extract_response_tool_calls(response_candidate)
  local tool_calls

  if response_candidate
        and response_candidate.content
        and response_candidate.content.parts
        and type(response_candidate.content.parts) == "table"
        and #response_candidate.content.parts > 0
  then
    for _, part in ipairs(response_candidate.content.parts) do
      if part.functionCall then
        tool_calls = tool_calls or {}

        table_insert(tool_calls, {
          ['id'] = "call_" .. uuid(),
          ['type'] = "function",
          ['function'] = {
            ['name'] = part.functionCall.name,
            ['arguments'] = cjson.encode(part.functionCall.args),
          },
        })
      end
    end

    return tool_calls
  end

  return nil
end

-- openai only supports a single string text part in response right now,
-- so concat all gemini response parts together
local function extract_response_content(response_candidate)
  if response_candidate
        and response_candidate.content
        and response_candidate.content.parts
        and type(response_candidate.content.parts) == "table"
        and #response_candidate.content.parts > 0
  then
    local content = {}
    for _, part in ipairs(response_candidate.content.parts) do
      if part.text then
        table_insert(content, part.text)
      end
    end

    return #content > 0 and table_concat(content, "\\n") or nil
  end

  return nil
end

local function from_gemini_chat_openai(response, model_info, route_type)
  local err
  if response and (type(response) == "string") then
    response, err = cjson.decode_with_array_mt(response)
  end

  if err then
    local err_client = "failed to decode response from Gemini"
    ngx.log(ngx.ERR, fmt("%s: %s", err_client, err))
    return nil, err_client
  end

  local kong_response = {}
  kong_response.model = model_info.name -- openai format always contains the model name

  if response.candidates and #response.candidates > 0 then
    -- for transformer plugins only
    if is_content_safety_failure(response) and
      (ai_plugin_base.has_filter_executed("ai-request-transformer-transform-request") or
        ai_plugin_base.has_filter_executed("ai-response-transformer-transform-response")) then

      local err = "transformation generation candidate breached Gemini content safety"
      ngx.log(ngx.ERR, err)

      return nil, err

    else
      -- process 'content' messages one by one
      for i, v in ipairs(response.candidates) do
        kong_response.choices = kong_response.choices or {}

        kong_response.choices[i] = {
          index = i - 1,
          message = {
            role = _OPENAI_ROLE_MAPPING[v.role or "model"],  -- default to openai 'assistant'
            content = extract_response_content(v),  -- may be nil
            tool_calls = extract_response_tool_calls(v),  -- may be nil
          },
          finish_reason = extract_response_finish_reason(v),
        }
      end

      if get_global_ctx("structured_output_mode")
       and #response.candidates[1].content.parts[1].text > 2
       and response.candidates[1].content.parts[1].text == "[]" then
        -- simulate OpenAI "refusal" where the question/answer doesn't fit the structured output schema
        kong_response.choices[1].message.content = nil
        kong_response.choices[1].message.refusal = "Kong: Vertex refused to answer the question, because it did not fit the structured output schema"
      end

      kong_response.object = "chat.completion"
      kong_response.model = response.modelVersion or model_info.name

      kong_response.created, err = ai_shared.iso_8601_to_epoch(response.createTime or ai_shared._CONST.UNIX_EPOCH)
      if err then
        ngx.log(ngx.WARN, "failed to convert createTime to epoch: ", err, ", fallback to 1970-01-01T00:00:00Z")
        kong_response.created = 0
      end

      kong_response.id = response.responseId or "chatcmpl-" .. uuid()
    end

    -- process analytics
    if response.usageMetadata then
      kong_response.usage = {
        prompt_tokens = response.usageMetadata.promptTokenCount,
        completion_tokens = response.usageMetadata.candidatesTokenCount,
        total_tokens = response.usageMetadata.totalTokenCount,
      }
    end

  elseif response.promptFeedback then
    kong_response = feedback_to_kong_error(response.promptFeedback)
    
    if get_global_ctx("stream_mode") then
      set_global_ctx("blocked_by_guard", kong_response)
    else
      kong.response.set_status(400)  -- safety call this in case we have already returned from e.g. another AI plugin

      -- This is duplicated DELIBERATELY - to avoid regression,
      -- moving it outside of the block above may cause bugs that
      -- we can't predict.
      if response.usageMetadata and
          (response.usageMetadata.promptTokenCount
          or response.usageMetadata.candidatesTokenCount
          or response.usageMetadata.totalTokenCount)
      then
        kong_response.usage = {
          prompt_tokens = response.usageMetadata.promptTokenCount,
          completion_tokens = response.usageMetadata.candidatesTokenCount,
          total_tokens = response.usageMetadata.totalTokenCount,
        }
      end
    end

  else -- probably a server fault or other unexpected response
    local err = "no generation candidates received from Gemini, or max_tokens too short"
    ngx.log(ngx.ERR, err)
    return nil, err

  end

  return cjson.encode(kong_response)
end

local transformers_to = {
  ["llm/v1/chat"] = to_gemini_chat_openai,
}

local transformers_from = {
  ["llm/v1/chat"] = from_gemini_chat_openai,
  ["stream/llm/v1/chat"] = handle_stream_event,
}

function _M.from_format(response_string, model_info, route_type)
  ngx.log(ngx.DEBUG, "converting from ", model_info.provider, "://", route_type, " type to kong")

  -- MUST return a string, to set as the response body
  if not transformers_from[route_type] then
    return nil, fmt("no transformer available from format %s://%s", model_info.provider, route_type)
  end

  -- try to get the ACTUAL model in use
  -- this is gemini-specific, as it supports many different drivers in one package
  local ok, model_t = pcall(ai_plugin_ctx.get_request_model_table_inuse)
  if not ok then
    -- set back to the plugin config's passed in object
    model_t = model_info
  end

  local coordinates = get_model_coordinates(model_t.name)

  if coordinates and coordinates.publisher == "anthropic" then
    -- use anthropic's transformer
    return anthropic.from_format(response_string, model_info, route_type)
  end
  -- otherwise, use the Gemini transformer

  if model_info.options and model_info.options ~= ngx.null and model_info.options.upstream_url and model_info.options.upstream_url ~= ngx.null then
    if string.find(model_info.options.upstream_url, "/endpoints/") then
      return openai.from_format(response_string, model_info, route_type)
    end
  end

  local ok, response_string, err, metadata = pcall(transformers_from[route_type], response_string, model_info, route_type)
  if not ok then
    err = response_string
  end
  if err then
    return nil, fmt("transformation failed from type %s://%s: %s",
                    model_info.provider,
                    route_type,
                    err or "unexpected_error"
                  )
  end

  return response_string, nil, metadata
end

function _M.to_format(request_table, model_info, route_type)
  ngx.log(ngx.DEBUG, "converting from kong type to ", model_info.provider, "/", route_type)

  if route_type == "preserve" then
    -- do nothing
    return request_table, nil, nil
  end

  if not transformers_to[route_type] then
    return nil, nil, fmt("no transformer for %s://%s", model_info.provider, route_type)
  end

  request_table = ai_shared.merge_config_defaults(request_table, model_info.options, model_info.route_type)

  local coordinates, err = get_model_coordinates(model_info.name)
  if err then
    return nil, nil, err
  end

  if coordinates and coordinates.publisher == "anthropic" then
    -- use anthropic transformer
    request_table.anthropic_version = (model_info.options and model_info.options.anthropic_version) or (request_table.anthropic_version) or "vertex-2023-10-16"
    assert(request_table.anthropic_version, "anthropic_version must be set for anthropic models")
    request_table.model = nil
    return anthropic.to_format(request_table, model_info, route_type)
  end
  -- otherwise, use the Gemini transformer

  if model_info.options and model_info.options ~= ngx.null and model_info.options.upstream_url and model_info.options.upstream_url ~= ngx.null then
    -- vertex ai model garden most model are openai compatible
    if string.find(model_info.options.upstream_url, "/endpoints/") then
      request_table.model = nil
      local req =  openai.to_format(request_table, model_info, route_type)
      -- request not accept model arg
      req.model = nil
      return req
    end
  end

  local ok, response_object, content_type, err = pcall(
    transformers_to[route_type],
    request_table,
    model_info
  )
  if err or (not ok) then
    return nil, nil, fmt("error transforming to %s://%s: %s", model_info.provider, route_type, err)
  end

  return response_object, content_type, nil
end

function _M.subrequest(body, conf, http_opts, return_res_table, identity_interface)
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

  local f_url = conf.model.options and conf.model.options.upstream_url

  if not f_url then  -- upstream_url override is not set
    -- check if this is "public" or "vertex" gemini deployment
    if is_vertex_mode(conf.model) then
      local err
      f_url, err = get_gemini_vertex_url(conf.model, conf.route_type, get_global_ctx("stream_mode"))
      if err then
        return nil, "failed to calculate vertex URL: " .. err
      end

    else
      -- 'consumer' Gemini mode
      f_url = ai_shared.upstream_url_format["gemini"] ..
              fmt(ai_shared.operation_map["gemini"][conf.route_type].path,
                  conf.model.name,
                  (get_global_ctx("stream_mode") and "streamGenerateContent" or "generateContent"))
    end
  end

  local method = ai_shared.operation_map[DRIVER_NAME][conf.route_type].method

  local auth_param_name = conf.auth and conf.auth.param_name
  local auth_param_value = conf.auth and conf.auth.param_value
  local auth_param_location = conf.auth and conf.auth.param_location

  local headers = {
    ["Accept"] = "application/json",
    ["Content-Type"] = "application/json",
  }

  if auth_param_name and auth_param_value and auth_param_location == "query" then
    f_url = fmt("%s?%s=%s", f_url, auth_param_name, auth_param_value)
  end

  if identity_interface and identity_interface.interface then
    if identity_interface.interface:needsRefresh() then
      -- HACK: A bug in lua-resty-gcp tries to re-load the environment
      --       variable every time, which fails in nginx
      --       Create a whole new interface instead.
      --       Memory leaks are mega unlikely because this should only
      --       happen about once an hour, and the old one will be
      --       cleaned up anyway.
      local service_account_json = identity_interface.interface.service_account_json
      identity_interface.interface.token = identity_interface.interface:new(service_account_json).token

      kong.log.debug("gcp identity token for ", kong.plugin.get_id(), " has been refreshed")
    end

    headers["Authorization"] = "Bearer " .. identity_interface.interface.token

  elseif conf.auth and conf.auth.header_name then
    headers[conf.auth.header_name] = conf.auth.header_value
  end

  local res, err, httpc = ai_shared.http_request(f_url, body_string, method, headers, http_opts, return_res_table)
  if err then
    return nil, nil, "request to ai service failed: " .. err
  end

  if return_res_table then
    return res, res.status, nil, httpc
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
  -- disable gzip for gemini because it breaks streaming
  kong.service.request.set_header("Accept-Encoding", "identity")

  return true, nil
end

-- returns err or nil
function _M.configure_request(conf, identity_interface)
  local model = ai_plugin_ctx.get_request_model_table_inuse()
  if not model or type(model) ~= "table" or model.provider ~= DRIVER_NAME then
    return nil, "invalid model parameter"
  end

  local parsed_url
  local f_url = model.options and model.options.upstream_url

  if not f_url then  -- upstream_url override is not set
    -- check if this is "public" or "vertex" gemini deployment
    if is_vertex_mode(model) then
      local err
      f_url, err = get_gemini_vertex_url(model, conf.route_type, get_global_ctx("stream_mode"))
      if err then
        return nil, "failed to calculate vertex URL: " .. err
      end

    else
      -- 'consumer' Gemini mode
      f_url = ai_shared.upstream_url_format["gemini"] ..
              fmt(ai_shared.operation_map["gemini"][conf.route_type].path,
                  model.name,
                  (get_global_ctx("stream_mode") and "streamGenerateContent" or "generateContent"))
    end
  end

  parsed_url = socket_url.parse(f_url)

  if model.options and model.options.upstream_path then
    -- upstream path override is set (or templated from request params)
    parsed_url.path = model.options.upstream_path
  end

  ai_shared.override_upstream_url(parsed_url, conf, model)


  -- if the path is read from a URL capture, ensure that it is valid
  parsed_url.path = (parsed_url.path and string_gsub(parsed_url.path, "^/*", "/")) or "/"

  kong.service.request.set_path(parsed_url.path)
  kong.service.request.set_scheme(parsed_url.scheme)
  local default_port = (parsed_url.scheme == "https") and 443 or 80
  kong.service.set_target(parsed_url.host, (tonumber(parsed_url.port) or default_port))

  local auth_header_name = conf.auth and conf.auth.header_name
  local auth_header_value = conf.auth and conf.auth.header_value
  local auth_param_name = conf.auth and conf.auth.param_name
  local auth_param_value = conf.auth and conf.auth.param_value
  local auth_param_location = conf.auth and conf.auth.param_location

  -- DBO restrictions makes sure that only one of these auth blocks runs in one plugin config
  if auth_header_name and auth_header_value then
    kong.service.request.set_header(auth_header_name, auth_header_value)
  end

  if auth_param_name and auth_param_value and auth_param_location == "query" then
    local query_table = kong.request.get_query()
    query_table[auth_param_name] = auth_param_value
    kong.service.request.set_query(query_table)
  end
  -- if auth_param_location is "form", it will have already been set in a global pre-request hook

  -- if we're passed a GCP SDK, for cloud identity / SSO, use it appropriately
  if identity_interface then
    if identity_interface:needsRefresh() then
      -- HACK: A bug in lua-resty-gcp tries to re-load the environment
      --       variable every time, which fails in nginx
      --       Create a whole new interface instead.
      --       Memory leaks are mega unlikely because this should only
      --       happen about once an hour, and the old one will be
      --       cleaned up anyway.
      local service_account_json = identity_interface.service_account_json
      local identity_interface_new = identity_interface:new(service_account_json)
      identity_interface.token = identity_interface_new.token

      kong.log.debug("gcp identity token for ", kong.plugin.get_id(), " has been refreshed")
    end

    kong.service.request.set_header("Authorization", "Bearer " .. identity_interface.token)
  end

  return true
end


_M.get_model_coordinates = get_model_coordinates


if _G._TEST then
  -- export locals for testing
  _M._to_tools = to_tools
  _M._to_gemini_chat_openai = to_gemini_chat_openai
  _M._from_gemini_chat_openai = from_gemini_chat_openai
  _M._openai_part_to_gemini_part = openai_part_to_gemini_part
  _M._is_vertex_mode = is_vertex_mode
  _M._get_gemini_vertex_url = get_gemini_vertex_url
  _M._extract_response_tool_calls = extract_response_tool_calls
  _M._extract_function_calls = extract_function_calls
  _M._openai_toolresult_to_gemini_toolresult = openai_toolresult_to_gemini_toolresult
end


return _M
