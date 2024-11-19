-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local ai_plugin_ctx = require("kong.llm.plugin.ctx")
local templater = require("kong.plugins.ai-prompt-template.templater")

local ipairs = ipairs
local type = type

local _M = {
  NAME = "render-prompt-template",
  STAGE = "REQ_TRANSFORMATION",
  }

local FILTER_OUTPUT_SCHEMA = {
  transformed = "boolean",
}

local _, set_ctx = ai_plugin_ctx.get_namespaced_accesors(_M.NAME, FILTER_OUTPUT_SCHEMA)


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



function _M:run(conf)
  if conf.log_original_request then
    kong.log.set_serialize_value(LOG_ENTRY_KEYS.REQUEST_BODY, kong.request.get_raw_body(conf.max_request_body_size))
  end

  -- if plugin ordering was altered, receive the "decorated" request
  local request_body_table = kong.request.get_body("application/json", nil, conf.max_request_body_size)
  if type(request_body_table) ~= "table" then
    return bad_request("this LLM route only supports application/json requests")
  end

  local messages = request_body_table.messages
  local prompt   = request_body_table.prompt

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
      return true -- not a reference, do nothing
    end

    return bad_request("this LLM route only supports templated requests")
  end

  local requested_template, err = find_template(template_name, conf.templates)
  if not requested_template then
    return bad_request(err)
  end

  -- try to render the replacement request
  local rendered_template, err = templater.render(requested_template, request_body_table.properties or {})
  if err then
    return bad_request(err)
  end

  kong.service.request.set_raw_body(rendered_template)

  set_ctx("transformed", true)
  return true
end


return _M
