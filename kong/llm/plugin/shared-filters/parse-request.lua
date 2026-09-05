local ai_plugin_ctx = require("kong.llm.plugin.ctx")
local ai_plugin_o11y = require("kong.llm.plugin.observability")
local fmt = string.format

local _M = {
  NAME = "parse-request",
  STAGE = "REQ_INTROSPECTION",
  DESCRIPTION = "parse the request body and early parse request headers",
}

local FILTER_OUTPUT_SCHEMA = {
  accept_gzip = "boolean",
  multipart_request = "boolean",
  request_body_table = "table",
  request_model = "table",
}

local _, set_ctx = ai_plugin_ctx.get_namespaced_accesors(_M.NAME, FILTER_OUTPUT_SCHEMA)
local get_global_ctx, set_global_ctx = ai_plugin_ctx.get_global_accessors(_M.NAME)


function _M:run(conf)
  -- This might be called again in retry, simply skip it as we already parsed the request
  if ngx.get_phase() == "balancer" then
    return true
  end

  -- record the request header very early, otherwise kong.serivce.request.set_header will polute it
  -- and only run this once, this function may be called multiple times by balancer
  if get_global_ctx("accept_gzip") == nil then
    set_global_ctx("accept_gzip", not not (kong.request.get_header("Accept-Encoding") or ""):match("%f[%a]gzip%f[%A]"))
  end

  if ai_plugin_ctx.has_namespace("ai-proxy-advanced-balance") then
    conf = ai_plugin_ctx.get_namespaced_ctx("ai-proxy-advanced-balance", "selected_target") or conf
  end

  -- first, calculate the coordinates of the request
  local content_type = kong.request.get_header("Content-Type") or "application/json"

  local request_table = kong.request.get_body(content_type, nil, conf.max_request_body_size)

  local multipart
  if not request_table then
    multipart = string.find(content_type, "multipart/form-data", nil, true)
    if not multipart then
      -- not a valid llm request, fall through
      return true
    end

    -- this may be a large file upload, so we have to proxy it directly
    set_ctx("multipart_request", true)
  end

  local adapter
  local llm_format = conf.llm_format
  if llm_format and llm_format ~= "openai" then
    local prev_adapter, source = get_global_ctx("llm_format_adapter")
    if prev_adapter then
      if prev_adapter.FORMAT_ID ~= llm_format then
        kong.log.warn("llm format changed from %s (%s) to %s, this is not supported", prev_adapter.FORMAT_ID, source, llm_format)
      else
        adapter = prev_adapter
      end
    end

    if not adapter then
      adapter = require(fmt("kong.llm.adapters.%s", llm_format))
      request_table = adapter:to_kong_req(request_table, kong)
      set_global_ctx("llm_format_adapter", adapter)
    end
  end

  request_table = ai_plugin_ctx.immutable_table(request_table)

  set_ctx("request_body_table", request_table)
  ai_plugin_ctx.set_request_body_table_inuse(request_table, _M.NAME)

  local req_model = {
    provider = adapter and adapter.FORMAT_ID or "UNSPECIFIED",
  }

  -- copy from the user request if present
  if not multipart and request_table and request_table.model then
    if type(request_table.model) == "string" then
      req_model.name = request_table.model
    end
  elseif multipart and req_model then
    req_model.name = "UNSPECIFIED"
  end

  req_model = ai_plugin_ctx.immutable_table(req_model)

  set_ctx("request_model", req_model)

  set_global_ctx("stream_mode", not not request_table.stream)

  ai_plugin_o11y.record_request_start()

  return true
end

return _M
