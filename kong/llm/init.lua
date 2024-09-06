local ai_shared = require("kong.llm.drivers.shared")
local re_match = ngx.re.match
local cjson = require("cjson.safe")
local fmt = string.format
local EMPTY = require("kong.tools.table").EMPTY


-- The module table
local _M = {
  config_schema = require "kong.llm.schemas",
}

do
  -- formats_compatible is a map of formats that are compatible with each other.
  local formats_compatible = {
    ["llm/v1/chat"] = {
      ["llm/v1/chat"] = true,
    },
    ["llm/v1/completions"] = {
      ["llm/v1/completions"] = true,
    },
  }



  -- identify_request determines the format of the request.
  -- It returns the format, or nil and an error message.
  -- @tparam table request The request to identify
  -- @treturn[1] string The format of the request
  -- @treturn[2] nil
  -- @treturn[2] string An error message if unidentified, or matching multiple formats
  local function identify_request(request)
    -- primitive request format determination
    local formats = {}

    if type(request.messages) == "table" and #request.messages > 0 then
      table.insert(formats, "llm/v1/chat")
    end

    if type(request.prompt) == "string" then
      table.insert(formats, "llm/v1/completions")
    end

    if formats[2] then
      return nil, "request matches multiple LLM request formats"
    elseif not formats_compatible[formats[1] or false] then
      return nil, "request format not recognised"
    else
      return formats[1]
    end
  end



  --- Check if a request is compatible with a route type.
  -- @tparam table request The request to check
  -- @tparam string route_type The route type to check against, eg. "llm/v1/chat"
  -- @treturn[1] boolean True if compatible
  -- @treturn[2] boolean False if not compatible
  -- @treturn[2] string Error message if not compatible
  -- @treturn[3] nil
  -- @treturn[3] string Error message if request format is not recognised
  function _M.is_compatible(request, route_type)
    if route_type == "preserve" then
      return true
    end

    local format, err = identify_request(request)
    if err then
      return nil, err
    end

    if formats_compatible[format][route_type] then
      return true
    end

    return false, fmt("[%s] message format is not compatible with [%s] route type", format, route_type)
  end
end


do
  ------------------------------------------------------------------------------
  -- LLM class implementation
  ------------------------------------------------------------------------------
  local LLM = {}
  LLM.__index = LLM



  function LLM:ai_introspect_body(request, system_prompt, http_opts, response_regex_match)
    local err, _

    -- set up the LLM request for transformation instructions
    local ai_request

    -- mistral, cohere, titan (via Bedrock) don't support system commands
    if self.conf.model.provider == "bedrock" then
      for _, p in ipairs(self.driver.bedrock_unsupported_system_role_patterns) do
        if self.conf.model.name:find(p) then
          ai_request = {
            messages = {
              [1] = {
                role = "user",
                content = system_prompt,
              },
              [2] = {
                role = "assistant",
                content = "What is the message?",
              },
              [3] = {
                role = "user",
                content = request,
              }
            },
            stream = false,
          }
          break
        end
      end
    end

    -- not Bedrock, or didn't match banned pattern - continue as normal
    if not ai_request then
      ai_request = {
        messages = {
          [1] = {
            role = "system",
            content = system_prompt,
          },
          [2] = {
            role = "user",
            content = request,
          }
        },
        stream = false,
      }
    end

    -- convert it to the specified driver format
    ai_request, _, err = self.driver.to_format(ai_request, self.conf.model, "llm/v1/chat")
    if err then
      return nil, err
    end

    -- run the shared logging/analytics/auth function
    ai_shared.pre_request(self.conf, ai_request)

    -- send it to the ai service
    local ai_response, _, err = self.driver.subrequest(ai_request, self.conf, http_opts, false, self.identity_interface)
    if err then
      return nil, "failed to introspect request with AI service: " .. err
    end

    -- parse and convert the response
    local ai_response, _, err = self.driver.from_format(ai_response, self.conf.model, self.conf.route_type)
    if err then
      return nil, "failed to convert AI response to Kong format: " .. err
    end

    -- run the shared logging/analytics function
    ai_shared.post_request(self.conf, ai_response)

    local ai_response, err = cjson.decode(ai_response)
    if err then
      return nil, "failed to convert AI response to JSON: " .. err
    end

    local new_request_body = ((ai_response.choices or EMPTY)[1].message or EMPTY).content
    if not new_request_body then
      return nil, "no 'choices' in upstream AI service response"
    end

    -- if specified, extract the first regex match from the AI response
    -- this is useful for AI models that pad with assistant text, even when
    -- we ask them NOT to.
    if response_regex_match then
      local matches, err = re_match(new_request_body, response_regex_match, "ijom")
      if err then
        return nil, "failed regex matching ai response: " .. err
      end

      if matches then
        new_request_body = matches[0]  -- this array DOES start at 0, for some reason

      else
        return nil, "AI response did not match specified regular expression"

      end
    end

    return new_request_body
  end



  -- Parse the response instructions.
  -- @tparam string|table in_body The response to parse, if a string, it will be parsed as JSON.
  -- @treturn[1] table The headers, field `in_body.headers`
  -- @treturn[1] string The body, field `in_body.body` (or if absent `in_body` itself as a table)
  -- @treturn[1] number The status, field `in_body.status` (or 200 if absent)
  -- @treturn[2] nil
  -- @treturn[2] string An error message if parsing failed or input wasn't a table
  function LLM:parse_json_instructions(in_body)
    local err
    if type(in_body) == "string" then
      in_body, err = cjson.decode(in_body)
      if err then
        return nil, nil, nil, err
      end
    end

    if type(in_body) ~= "table" then
      return nil, nil, nil, "input not table or string"
    end

    return
      in_body.headers,
      in_body.body or in_body,
      in_body.status or 200
  end



  --- Instantiate a new LLM driver instance.
  -- @tparam table conf Configuration table
  -- @tparam table http_opts HTTP options table
  -- @tparam table [optional] cloud-authentication identity interface
  -- @treturn[1] table A new LLM driver instance
  -- @treturn[2] nil
  -- @treturn[2] string An error message if instantiation failed
  function _M.new_driver(conf, http_opts, identity_interface)
    local self = {
      conf = conf or {},
      http_opts = http_opts or {},
      identity_interface = identity_interface,  -- 'or nil'
    }
    setmetatable(self, LLM)

    self.provider = (self.conf.model or {}).provider or "NONE_SET"
    local driver_module = "kong.llm.drivers." .. self.provider

    local ok
    ok, self.driver = pcall(require, driver_module)
    if not ok then
      local err = "could not instantiate " .. driver_module .. " package"
      kong.log.err(err)
      return nil, err
    end

    return self
  end

end


return _M
