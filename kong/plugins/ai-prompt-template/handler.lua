
local templater = require("kong.plugins.ai-prompt-template.templater")
local llm_state = require("kong.llm.state")
local ipairs = ipairs
local type = type



local AIPromptTemplateHandler = {
  PRIORITY = 773,
  VERSION = require("kong.meta").version,
}



local LOG_ENTRY_KEYS = {
  REQUEST_BODY = "ai.payload.original_request",
}



local function bad_request(msg)
  kong.log.debug(msg)
  return kong.response.exit(400, { error = { message = msg } })
end



-- Checks if the passed in reference looks like a reference, and returns the template name.
-- Valid references start with '{template://' and end with '}'.
-- @tparam string reference reference to check
-- @treturn string the reference template name or nil if it's not a reference
local function extract_template_name(reference)
  if type(reference) ~= "string" then
    return nil
  end

  if not (reference:sub(1, 12) == "{template://" and reference:sub(-1) == "}") then
    return nil
  end

  return reference:sub(13, -2)
end



--- Find a template by name in the list of templates.
-- @tparam string reference_name the name of the template to find
-- @tparam table templates the list of templates to search
-- @treturn string the template if found, or nil + error message if not found
local function find_template(reference_name, templates)
  for _, v in ipairs(templates) do
    if v.name == reference_name then
      return v, nil
    end
  end

  return nil, "could not find template name [" .. reference_name .. "]"
end



function AIPromptTemplateHandler:access(conf)
  kong.service.request.enable_buffering()
  llm_state.set_prompt_templated()

  if conf.log_original_request then
    kong.log.set_serialize_value(LOG_ENTRY_KEYS.REQUEST_BODY, kong.request.get_raw_body(conf.max_request_body_size))
  end

  local request = kong.request.get_body("application/json", nil, conf.max_request_body_size)
  if type(request) ~= "table" then
    return bad_request("this LLM route only supports application/json requests")
  end

  local messages = request.messages
  local prompt   = request.prompt

  if messages and prompt then
    return bad_request("cannot run 'messages' and 'prompt' templates at the same time")
  end

  local reference = messages or prompt
  if not reference then
    return bad_request("only 'llm/v1/chat' and 'llm/v1/completions' formats are supported for templating")
  end

  local template_name = extract_template_name(reference)
  if not template_name then
    if conf.allow_untemplated_requests then
      return  -- not a reference, do nothing
    end

    return bad_request("this LLM route only supports templated requests")
  end

  local requested_template, err = find_template(template_name, conf.templates)
  if not requested_template then
    return bad_request(err)
  end

  -- try to render the replacement request
  local rendered_template, err = templater.render(requested_template, request.properties or {})
  if err then
    return bad_request(err)
  end

  kong.service.request.set_raw_body(rendered_template)
end


return AIPromptTemplateHandler
