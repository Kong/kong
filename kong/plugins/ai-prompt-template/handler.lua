local _M = {}

-- imports
local kong_meta = require "kong.meta"
local templater = require("kong.plugins.ai-prompt-template.templater"):new()
local fmt       = string.format
local parse_url = require("socket.url").parse
local byte      = string.byte
local sub       = string.sub
local type      = type
local byte      = byte
--

_M.PRIORITY = 773
_M.VERSION = kong_meta.version


local log_entry_keys = {
  REQUEST_BODY = "ai.payload.original_request",
}

local function bad_request(msg)
  kong.log.debug(msg)
  return kong.response.exit(ngx.HTTP_BAD_REQUEST, { error = { message = msg } })
end

local BRACE_START = byte("{")
local BRACE_END = byte("}")
local COLON = byte(":")
local SLASH = byte("/")

---- BORROWED FROM `kong.pdk.vault`
---
-- Checks if the passed in reference looks like a reference.
-- Valid references start with '{template://' and end with '}'.
--
-- @local
-- @function is_reference
-- @tparam string reference reference to check
-- @treturn boolean `true` is the passed in reference looks like a reference, otherwise `false`
local function is_reference(reference)
  return type(reference)      == "string"
     and byte(reference, 1)   == BRACE_START
     and byte(reference, -1)  == BRACE_END
     and byte(reference, 10)   == COLON
     and byte(reference, 11)   == SLASH
     and byte(reference, 12)   == SLASH
     and sub(reference, 2, 9) == "template"
end

local function find_template(reference_string, templates)
  local parts, err = parse_url(sub(reference_string, 2, -2))
  if not parts then
    return nil, fmt("template reference is not in format '{template://template_name}' (%s) [%s]", err, reference_string)
  end

  -- iterate templates to find it
  for i, v in ipairs(templates) do
    if v.name == parts.host then
      return v, nil
    end
  end

  return nil, fmt("could not find template name [%s]", parts.host)
end

function _M:access(conf)
  kong.service.request.enable_buffering()
  kong.ctx.shared.ai_prompt_templated = true

  if conf.log_original_request then
    kong.log.set_serialize_value(log_entry_keys.REQUEST_BODY, kong.request.get_raw_body())
  end

  local request, err = kong.request.get_body("application/json")
  if err then
    return bad_request("this LLM route only supports application/json requests")
  end

  if (not request.messages) and (not request.prompt) then
    return bad_request("this LLM route only supports llm/chat or llm/completions type requests")
  end

  if request.messages and request.prompt then
    return bad_request("cannot run 'messages' and 'prompt' templates at the same time")
  end

  local reference
  if request.messages then
    reference = request.messages

  elseif request.prompt then
    reference = request.prompt

  else
    return bad_request("only 'llm/v1/chat' and 'llm/v1/completions' formats are supported for templating")
  end

  if is_reference(reference) then
    local requested_template, err = find_template(reference, conf.templates)
    if not requested_template then
      return bad_request(err)
    end

    -- try to render the replacement request
    local rendered_template, err = templater:render(requested_template, request.properties or {})
    if err then
      return bad_request(err)
    end

    kong.service.request.set_raw_body(rendered_template)

  elseif not (conf.allow_untemplated_requests) then
    return bad_request("this LLM route only supports templated requests")
  end
end


return _M
