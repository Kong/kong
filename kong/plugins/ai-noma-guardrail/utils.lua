-- +-------------------------------------------------------------+
--
--           Noma Security Guardrail Plugin for Kong
--                       https://noma.security
--
-- Shared utilities for scan result processing and format conversion
--
-- +-------------------------------------------------------------+

local cjson = require("cjson.safe")

local _M = {}


-- Detector keys that indicate sensitive data (can be anonymized instead of blocked)
local ANONYMIZABLE_DETECTOR_KEYS = {
  sensitiveData = true,
  dataDetector = true,
}


-------------------------------------------------------------------------------
-- Scan Result Processing
-------------------------------------------------------------------------------

--- Check if a detector result indicates a positive match
-- @param result_obj table Detector result object
-- @return boolean True if result=true
local function is_positive_result(result_obj)
  return type(result_obj) == "table" and result_obj.result == true
end


--- Analyze classification results to determine if only anonymizable detectors triggered
-- @param classification table Classification results from scan
-- @return boolean True if only sensitive data detectors triggered (safe to anonymize)
local function only_anonymizable_detectors_triggered(classification)
  if not classification then
    return false
  end

  local has_sensitive_data = false
  local has_blocking_detectors = false

  for key, value in pairs(classification) do
    if ANONYMIZABLE_DETECTOR_KEYS[key] and type(value) == "table" then
      -- Check anonymizable detectors (sensitiveData, dataDetector)
      for _, detector_result in pairs(value) do
        if is_positive_result(detector_result) then
          has_sensitive_data = true
        end
      end

    elseif type(value) == "table" then
      if value.result ~= nil then
        -- Direct detector result
        if is_positive_result(value) then
          has_blocking_detectors = true
        end
      else
        -- Nested detector group
        for _, nested_result in pairs(value) do
          if is_positive_result(nested_result) then
            has_blocking_detectors = true
          end
        end
      end
    end
  end

  return has_sensitive_data and not has_blocking_detectors
end


--- Extract anonymized content from Noma scan response for a specific role
-- @param scan_response table Noma API response
-- @param role string Message role ("user" or "assistant")
-- @return string|nil Anonymized content if available
function _M.extract_anonymized_content(scan_response, role)
  local scan_result = scan_response.scanResult
  if not scan_result or type(scan_result) ~= "table" then
    return nil
  end

  for _, result_item in ipairs(scan_result) do
    if result_item.role == role then
      local results = result_item.results
      if results
         and results.anonymizedContent
         and results.anonymizedContent.anonymized then
        return results.anonymizedContent.anonymized
      end
    end
  end

  return nil
end


--- Determine if content should be anonymized based on scan results and config
-- @param scan_response table Noma API response
-- @param conf table Plugin configuration
-- @param role string Message role ("user" or "assistant")
-- @return boolean True if content should be anonymized
function _M.should_anonymize(scan_response, conf, role)
  -- Never anonymize in monitor mode or when anonymization is disabled
  if conf.monitor_mode or not conf.anonymize_input then
    return false
  end

  local is_unsafe = scan_response.aggregatedScanResult

  -- If content is safe, anonymize if available (replaces PII with placeholders)
  if not is_unsafe then
    return true
  end

  -- If unsafe, only anonymize if solely sensitive data detectors triggered
  local scan_result = scan_response.scanResult
  if not scan_result or type(scan_result) ~= "table" then
    return false
  end

  for _, result_item in ipairs(scan_result) do
    if result_item.role == role then
      return only_anonymizable_detectors_triggered(result_item.results)
    end
  end

  return false
end


-------------------------------------------------------------------------------
-- Format Conversion: OpenAI Chat Completion -> Responses API
-------------------------------------------------------------------------------

--- Convert OpenAI image_url format to Responses API input_image format
-- @param image_url string|table OpenAI image URL (string or {url, detail} table)
-- @return table Responses API input_image object
local function convert_image_to_responses_format(image_url)
  local url = type(image_url) == "string" and image_url or (image_url and image_url.url)
  if not url then
    return nil
  end

  return {
    type = "input_image",
    image_url = url,
    detail = type(image_url) == "table" and image_url.detail or "auto",
  }
end


--- Get the appropriate text type for a role in Responses API format
-- @param role string Message role
-- @return string "input_text" for user/system, "output_text" for assistant
local function get_text_type_for_role(role)
  return role == "assistant" and "output_text" or "input_text"
end


--- Convert message content to Responses API content items
-- @param content string|table Message content (string or array of content parts)
-- @param text_type string Text type to use ("input_text" or "output_text")
-- @return table Array of Responses API content items
local function convert_content_to_responses_format(content, text_type)
  local content_items = {}

  if type(content) == "string" then
    table.insert(content_items, { type = text_type, text = content })
    return content_items
  end

  if type(content) ~= "table" then
    return content_items
  end

  for _, item in ipairs(content) do
    if type(item) == "string" then
      table.insert(content_items, { type = text_type, text = item })

    elseif type(item) == "table" then
      local item_type = item.type

      if item_type == "text" then
        table.insert(content_items, { type = text_type, text = item.text or "" })

      elseif item_type == "image_url" then
        local image_item = convert_image_to_responses_format(item.image_url)
        if image_item then
          table.insert(content_items, image_item)
        end

      elseif item_type == "input_text" or item_type == "output_text"
          or item_type == "input_image" or item_type == "input_file" then
        -- Already in Responses API format, pass through
        table.insert(content_items, item)

      else
        -- Unknown type, try to extract text
        if item.text then
          table.insert(content_items, { type = text_type, text = item.text })
        end
      end
    end
  end

  return content_items
end


--- Convert a tool call message to Responses API function_call items
-- @param tool_calls table Array of tool calls from assistant message
-- @return table Array of Responses API function_call items
local function convert_tool_calls_to_responses_format(tool_calls)
  local items = {}

  for _, tool_call in ipairs(tool_calls) do
    local func = tool_call["function"]
    if func then
      table.insert(items, {
        type = "function_call",
        call_id = tool_call.id,
        name = func.name,
        arguments = func.arguments,
      })
    end
  end

  return items
end


--- Convert OpenAI chat completion messages to Noma Responses API format
-- @param messages table Array of OpenAI chat completion messages
-- @return table Array of Responses API input items
function _M.messages_to_responses_api(messages)
  local input_items = {}

  for _, msg in ipairs(messages) do
    local role = msg.role
    local content = msg.content
    local tool_calls = msg.tool_calls
    local tool_call_id = msg.tool_call_id

    if role == "tool" then
      -- Tool response -> function_call_output
      table.insert(input_items, {
        type = "function_call_output",
        call_id = tool_call_id,
        output = type(content) == "string" and content or cjson.encode(content),
      })

    elseif role == "assistant" and tool_calls and type(tool_calls) == "table" and #tool_calls > 0 then
      -- Assistant with tool calls -> function_call items
      for _, item in ipairs(convert_tool_calls_to_responses_format(tool_calls)) do
        table.insert(input_items, item)
      end

    elseif content ~= nil then
      -- Regular message (user, assistant, system)
      local text_type = get_text_type_for_role(role)
      local content_items = convert_content_to_responses_format(content, text_type)

      if #content_items > 0 then
        table.insert(input_items, {
          type = "message",
          role = role,
          content = content_items,
        })
      end
    end
  end

  return input_items
end


-------------------------------------------------------------------------------
-- Response Body Utilities
-------------------------------------------------------------------------------

--- Extract assistant content from LLM response body
-- @param response_body string JSON response body from LLM
-- @return string|nil Assistant content if found
function _M.extract_assistant_content(response_body)
  if not response_body then
    return nil
  end

  local response_json, err = cjson.decode(response_body)
  if not response_json then
    kong.log.debug("failed to decode response body: ", err)
    return nil
  end

  -- OpenAI chat completion format
  local choices = response_json.choices
  if choices and type(choices) == "table" and #choices > 0 then
    local first_choice = choices[1]
    if first_choice then
      -- Chat completion format
      if first_choice.message and first_choice.message.content then
        return first_choice.message.content
      end
      -- Text completion format
      if first_choice.text then
        return first_choice.text
      end
    end
  end

  -- Direct content field
  if response_json.content then
    return response_json.content
  end

  -- Direct text field
  if response_json.text then
    return response_json.text
  end

  return nil
end


--- Replace assistant content in LLM response body
-- @param response_body string Original JSON response body
-- @param new_content string New content to replace with
-- @return string|nil Modified response body on success
-- @return string|nil Error message on failure
function _M.replace_assistant_content(response_body, new_content)
  local response_json, err = cjson.decode(response_body)
  if not response_json then
    return nil, err
  end

  local choices = response_json.choices
  if choices and type(choices) == "table" and #choices > 0 then
    local first_choice = choices[1]
    if first_choice then
      if first_choice.message then
        first_choice.message.content = new_content
      elseif first_choice.text ~= nil then
        first_choice.text = new_content
      end
    end
  end

  return cjson.encode(response_json)
end


--- Create a blocked response body
-- @return string JSON error response
function _M.create_blocked_response()
  return cjson.encode({
    error = {
      message = "Response blocked by Noma guardrail",
      type = "guardrail_blocked",
    }
  })
end


-- Expose internals for testing
if _G._TEST then
  _M._is_positive_result = is_positive_result
  _M._only_anonymizable_detectors_triggered = only_anonymizable_detectors_triggered
  _M._convert_content_to_responses_format = convert_content_to_responses_format
  _M._get_text_type_for_role = get_text_type_for_role
end


return _M
