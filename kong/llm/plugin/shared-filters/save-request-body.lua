local ai_plugin_ctx = require("kong.llm.plugin.ctx")

local _M = {
  NAME = "save-request-body",
  STAGE = "REQ_INTROSPECTION",
  DESCRIPTION = "save the raw request body if needed",
}

local FILTER_OUTPUT_SCHEMA = {
  raw_request_body = "string",
}

local _, set_ctx = ai_plugin_ctx.get_namespaced_accesors(_M.NAME, FILTER_OUTPUT_SCHEMA)


function _M:run(conf)
  -- This might be called again in retry, simply skip it as we already parsed the request
  if ngx.get_phase() == "balancer" then
    return true
  end

  local log_request_body = false
  if conf.logging then
    log_request_body = not not conf.logging.log_payloads
  elseif conf.targets ~= nil then
    -- For ai-proxy-advanced, we store the raw request body if any target wants to log the request payload
    for _, target in ipairs(conf.targets) do
      if target.logging and target.logging.log_payloads then
        log_request_body = true
        break
      end
    end
  end

  if log_request_body then
    -- This is the raw request body which is sent by the client. The request_body_table key is similar to this,
    -- but it is in openai format which is converted from other LLM vendors' format in parse_xxx_request.
    -- Note we save the unmodified request body (not even json decode then encode).
    set_ctx("raw_request_body", kong.request.get_raw_body(conf.max_request_body_size))
  end

  return true
end

return _M
