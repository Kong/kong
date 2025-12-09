-- +-------------------------------------------------------------+
--
--           Noma Security Guardrail Plugin for Kong
--                       https://noma.security
--
-- Combined guardrail filter using subrequest pattern
-- Handles both pre-request and post-response checks in a single flow
--
-- +-------------------------------------------------------------+

local http = require("resty.http")
local cjson = require("cjson.safe")
local ai_plugin_ctx = require("kong.llm.plugin.ctx")
local kong_utils = require("kong.tools.gzip")
local noma_client = require("kong.plugins.ai-noma-guardrail.client")
local noma_utils = require("kong.plugins.ai-noma-guardrail.utils")

local _M = {
  NAME = "noma-guardrail",
  STAGE = "REQ_TRANSFORMATION",
  DESCRIPTION = "Check prompts and responses with Noma AI-DR using subrequest pattern",
}

local FILTER_OUTPUT_SCHEMA = {
  pre_checked = "boolean",
  pre_blocked = "boolean",
  pre_anonymized = "boolean",
  post_checked = "boolean",
  post_blocked = "boolean",
  post_anonymized = "boolean",
  scan_result = "table",
}

local _, set_ctx = ai_plugin_ctx.get_namespaced_accesors(_M.NAME, FILTER_OUTPUT_SCHEMA)
local get_global_ctx, set_global_ctx = ai_plugin_ctx.get_global_accessors(_M.NAME)


-------------------------------------------------------------------------------
-- HTTP Helpers
-------------------------------------------------------------------------------

--- Make subrequest to upstream LLM
-- @param httpc HTTP client instance
-- @param request_body string Request body to send
-- @param http_opts table HTTP options
-- @return table|nil Response object on success
-- @return string|nil Error message on failure
local function subrequest(httpc, request_body, http_opts)
  httpc:set_timeouts(http_opts.timeout or 60000)

  local upstream_uri = ngx.var.upstream_uri
  if ngx.var.is_args == "?" or string.sub(ngx.var.request_uri, -1) == "?" then
    ngx.var.upstream_uri = upstream_uri .. "?" .. (ngx.var.args or "")
  end

  local ok, err = httpc:connect({
    scheme = ngx.var.upstream_scheme,
    host = ngx.ctx.balancer_data.host,
    port = ngx.ctx.balancer_data.port,
    proxy_opts = http_opts.proxy_opts,
    ssl_verify = http_opts.ssl_verify,
    ssl_server_name = ngx.ctx.balancer_data.host,
  })

  if not ok then
    return nil, "failed to connect to upstream: " .. err
  end

  local headers = kong.request.get_headers()
  headers["transfer-encoding"] = nil  -- hop-by-hop, strip it
  headers["content-length"] = nil     -- will be set by resty-http

  if ngx.var.upstream_host == "" then
    headers["host"] = nil
  else
    headers["host"] = ngx.var.upstream_host
  end

  local res, req_err = httpc:request({
    method = kong.request.get_method(),
    path = ngx.var.upstream_uri,
    headers = headers,
    body = request_body,
  })

  if not res then
    return nil, "subrequest failed: " .. req_err
  end

  return res
end


-------------------------------------------------------------------------------
-- Pre-request Check
-------------------------------------------------------------------------------

--- Check user prompt with Noma before sending to LLM
-- @param request_body_table table Parsed request body
-- @param conf table Plugin configuration
-- @param http_opts table HTTP options for Noma API
-- @return boolean True if allowed, false if blocked
-- @return string|nil Anonymized request body if anonymized
-- @return string|nil Error message if blocked
local function check_pre_request(request_body_table, conf, http_opts)
  local messages = request_body_table.messages
  if not messages or type(messages) ~= "table" or #messages == 0 then
    return true, nil, nil  -- No messages to check
  end

  -- Convert to Responses API format
  local input_items = noma_utils.messages_to_responses_api(messages)
  if #input_items == 0 then
    return true, nil, nil
  end

  -- Call Noma API
  local scan_response, err = noma_client.scan({ input = input_items }, conf, http_opts)

  if not scan_response then
    kong.log.err("Noma pre-request API call failed: ", err)
    if conf.block_failures then
      return false, nil, "Noma guardrail check failed"
    end
    kong.log.warn("Noma API failed but allowing request through (block_failures=false)")
    return true, nil, nil
  end

  set_ctx("scan_result", scan_response)
  set_ctx("pre_checked", true)

  local is_unsafe = scan_response.aggregatedScanResult

  -- Monitor mode: log and allow through
  if conf.monitor_mode then
    if is_unsafe then
      kong.log.warn("Noma guardrail would have blocked request (monitor mode)")
    end
    return true, nil, nil
  end

  -- Content is safe
  if not is_unsafe then
    kong.log.debug("Noma guardrail allowed request")
    return true, nil, nil
  end

  -- Content is unsafe - check if we can anonymize instead of block
  if noma_utils.should_anonymize(scan_response, conf, "user") then
    local anonymized = noma_utils.extract_anonymized_content(scan_response, "user")
    if anonymized then
      -- Replace user message content
      for i = #messages, 1, -1 do
        if messages[i].role == "user" then
          messages[i].content = anonymized
          break
        end
      end
      set_ctx("pre_anonymized", true)
      kong.log.info("Noma guardrail anonymized user message")
      local new_body = cjson.encode(request_body_table)
      return true, new_body, nil
    end
  end

  -- Block the request
  set_ctx("pre_blocked", true)
  kong.log.info("Noma guardrail blocked request")
  return false, nil, "Request blocked by Noma guardrail"
end


-------------------------------------------------------------------------------
-- Post-response Check
-------------------------------------------------------------------------------

--- Build Noma scan payload for assistant response
-- @param content string Assistant response content
-- @return table Noma API payload
local function build_response_scan_payload(content)
  return {
    input = {
      {
        type = "message",
        role = "assistant",
        content = {
          { type = "output_text", text = content }
        }
      }
    }
  }
end


--- Check LLM response with Noma
-- @param response_body string Response body from LLM
-- @param conf table Plugin configuration
-- @param http_opts table HTTP options for Noma API
-- @return boolean True if allowed, false if blocked
-- @return string|nil Modified response body if anonymized
-- @return string|nil Error message if blocked
local function check_post_response(response_body, conf, http_opts)
  -- Extract assistant content
  local assistant_content = noma_utils.extract_assistant_content(response_body)
  if not assistant_content or assistant_content == "" then
    kong.log.debug("Noma post-response: no assistant content found")
    return true, nil, nil
  end

  -- Call Noma API
  local payload = build_response_scan_payload(assistant_content)
  local scan_response, err = noma_client.scan(payload, conf, http_opts)

  if not scan_response then
    kong.log.err("Noma post-response API call failed: ", err)
    if conf.block_failures then
      return false, nil, "Noma guardrail response check failed"
    end
    kong.log.warn("Noma API failed but allowing response through (block_failures=false)")
    return true, nil, nil
  end

  set_ctx("post_checked", true)

  local is_unsafe = scan_response.aggregatedScanResult

  -- Monitor mode: log and allow through
  if conf.monitor_mode then
    if is_unsafe then
      kong.log.warn("Noma guardrail would have blocked response (monitor mode)")
    end
    return true, nil, nil
  end

  -- Content is safe
  if not is_unsafe then
    kong.log.debug("Noma guardrail allowed response")
    return true, nil, nil
  end

  -- Content is unsafe - check if we can anonymize instead of block
  if noma_utils.should_anonymize(scan_response, conf, "assistant") then
    local anonymized = noma_utils.extract_anonymized_content(scan_response, "assistant")
    if anonymized then
      local new_body, replace_err = noma_utils.replace_assistant_content(response_body, anonymized)
      if new_body then
        set_ctx("post_anonymized", true)
        kong.log.info("Noma guardrail anonymized response content")
        return true, new_body, nil
      end
      kong.log.err("Failed to replace assistant content: ", replace_err)
    end
  end

  -- Block the response
  set_ctx("post_blocked", true)
  kong.log.info("Noma guardrail blocked response")
  return false, nil, "Response blocked by Noma guardrail"
end


-------------------------------------------------------------------------------
-- Filter Entry Point
-------------------------------------------------------------------------------

function _M:run(conf)
  -- Skip if both checks are disabled
  if not conf.check_prompt and not conf.check_response then
    kong.log.debug("Noma guardrail disabled (both checks off)")
    return true
  end

  -- Check if balancer data is available (set by ai-proxy)
  if not ngx.ctx.balancer_data then
    kong.log.debug("Noma guardrail: no balancer data, skipping subrequest pattern")
    return true
  end

  -- Get request body
  local request_body = kong.request.get_raw_body(conf.max_request_body_size)
  if not request_body then
    kong.log.debug("Noma guardrail: no request body")
    return true
  end

  local request_body_table = cjson.decode(request_body)
  if not request_body_table then
    kong.log.debug("Noma guardrail: failed to parse request body as JSON")
    return true
  end

  local http_opts = noma_client.build_http_opts(conf)
  local final_request_body = request_body

  -- Pre-request check
  if conf.check_prompt then
    local allowed, anonymized_body, err = check_pre_request(request_body_table, conf, http_opts)
    if not allowed then
      return kong.response.exit(400, { error = { message = err } })
    end
    if anonymized_body then
      final_request_body = anonymized_body
    end
  end

  -- Make subrequest to upstream LLM
  kong.log.debug("Noma guardrail: making subrequest to upstream")
  local httpc = http.new()
  local res, subreq_err = subrequest(httpc, final_request_body, {
    timeout = conf.http_timeout,
    ssl_verify = conf.https_verify,
    proxy_opts = http_opts.proxy_opts,
  })

  if not res then
    kong.log.err("Noma guardrail: subrequest failed: ", subreq_err)
    return kong.response.exit(502, { error = { message = "Failed to connect to LLM service" } })
  end

  -- Read response body
  local response_body = res:read_body()
  local response_headers = res.headers or {}
  local response_status = res.status

  -- Decompress if gzipped
  local is_gzip = response_headers["Content-Encoding"] == "gzip"
  if is_gzip and response_body then
    response_body = kong_utils.inflate_gzip(response_body)
  end

  -- Post-response check (only for successful responses)
  if conf.check_response and response_status == 200 and response_body then
    local allowed, modified_body, err = check_post_response(response_body, conf, http_opts)
    if not allowed then
      return kong.response.exit(400, { error = { message = err } })
    end
    if modified_body then
      response_body = modified_body
    end
  end

  -- Clean up response headers
  response_headers["content-length"] = nil
  response_headers["content-encoding"] = nil
  response_headers["transfer-encoding"] = nil

  -- Mark that we're handling the response
  set_global_ctx("response_body_sent", true)

  -- Return final response
  return kong.response.exit(response_status, response_body, response_headers)
end


-- Expose for testing
if _G._TEST then
  _M._check_pre_request = check_pre_request
  _M._check_post_response = check_post_response
  _M._subrequest = subrequest
end


return _M
