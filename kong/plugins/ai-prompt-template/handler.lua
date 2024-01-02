local _M = {}

-- imports
local kong_meta      = require "kong.meta"
local templater      = require("kong.plugins.ai-prompt-template.templater"):new()
local fmt            = string.format
local parse_url      = require("socket.url").parse
local byte           = string.byte
local sub            = string.sub
local cjson          = require("cjson.safe")
--

_M.PRIORITY = 773
_M.VERSION = kong_meta.version


local log_entry_keys = {
  REQUEST_BODY = "ai.payload.original_request",
}

local function do_bad_request(msg)
  kong.log.warn(msg)
  kong.response.exit(400, { error = true, message = msg })
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
  if is_reference(reference_string) then
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

    return nil, "could not find template name [" .. parts.host .. "]"
  else
    return nil, "'messages' field should be a single string, in format '{template://template_name}'"
  end
end

function _M:access(conf)
  kong.log.debug("IN: ai-prompt-template/access")
  kong.service.request.enable_buffering()
  kong.ctx.shared.prompt_templated = true
  
  if conf.log_original_request then
    kong.log.set_serialize_value(log_entry_keys.REQUEST_BODY, kong.request.get_raw_body())
  end

  -- if plugin ordering was altered from a previous AI-family plugin, use the replacement request
  local request, err
  if not kong.ctx.replacement_request then
    request, err = kong.request.get_body("application/json")

    if err then
      do_bad_request("ai-prompt-template only supports application/json requests")
    end
  else
    request = kong.ctx.replacement_request
  end

  if (not request.messages) and (not request.prompt) then
    do_bad_request("ai-prompt-template only support llm/chat or llm/completions type requests")
  end

  local format, reference

  -- TODO MOVE ALL THIS TO CACHE BLOCK
  if request.messages and (not request.prompt) then
    format = "llm/v1/chat"
    reference = request.messages

  elseif request.prompt and (not request.messages) then
    format = "llm/v1/completions"
    reference = request.prompt

  elseif request.messages and request.prompt then
    do_bad_request("cannot run 'messages' and 'prompt' templates at the same time")

  else
    do_bad_request("only 'llm/v1/chat' and 'llm/v1/completions' formats are supported for templating")
  end

  local requested_template, err = find_template(reference, conf.templates)
  if err and (not conf.allow_untemplated_requests) then do_bad_request(err) end

  if not err then
    -- try to render the replacement request
    local rendered_template, err = templater:render(requested_template, format, request.properties or {})
    if err then do_bad_request(err) end

    -- stash the result for parsing later (in ai-proxy etcetera)
    kong.log.inspect("template-rendered request: ", rendered_template)
    kong.service.request.set_raw_body(rendered_template)

    local result, err = cjson.decode(rendered_template)
    if err then do_bad_request("failed to parse template to JSON: " .. err) end

    kong.ctx.shared.replacement_request = result
  end

  -- all good
  kong.log.debug("OUT: ai-prompt-template/access")
end


return _M
