local _M = {}

-- imports
local ai_shared = require("kong.llm.drivers.shared")
local ai_module = require("kong.llm")
local llm = require("kong.llm")
local cjson = require("cjson.safe")
local kong_utils = require("kong.tools.gzip")
local kong_meta = require("kong.meta")
--


_M.PRIORITY = 770
_M.VERSION = kong_meta.version


-- reuse this table for error message response
local ERROR_MSG = { error = { message = "" } }


local function bad_request(msg)
  kong.log.warn(msg)
  ERROR_MSG.error.message = msg

  return kong.response.exit(400, ERROR_MSG)
end


local function internal_server_error(msg)
  kong.log.err(msg)
  ERROR_MSG.error.message = msg

  return kong.response.exit(500, ERROR_MSG)
end


function _M:header_filter(conf)
  if kong.ctx.shared.skip_response_transformer then
    return
  end

  -- clear shared restricted headers
  for _, v in ipairs(ai_shared.clear_response_headers.shared) do
    kong.response.clear_header(v)
  end

  -- only act on 200 in first release - pass the unmodifed response all the way through if any failure
  if kong.response.get_status() ~= 200 then
    return
  end

  local response_body = kong.service.response.get_raw_body()
  if not response_body then
    return
  end

  local ai_driver = require("kong.llm.drivers." .. conf.model.provider)
  local route_type = conf.route_type

  local is_gzip = kong.response.get_header("Content-Encoding") == "gzip"
  if is_gzip then
    response_body = kong_utils.inflate_gzip(response_body)
  end
  
  if route_type == "preserve" then
    kong.ctx.plugin.parsed_response = response_body
  else
    local new_response_string, err = ai_driver.from_format(response_body, conf.model, route_type)
    if err then
      kong.ctx.plugin.ai_parser_error = true

      ngx.status = 500
      ERROR_MSG.error.message = err

      kong.ctx.plugin.parsed_response = cjson.encode(ERROR_MSG)

    elseif new_response_string then
      -- preserve the same response content type; assume the from_format function
      -- has returned the body in the appropriate response output format
      kong.ctx.plugin.parsed_response = new_response_string
    end
  end

  ai_driver.post_request(conf)
end


function _M:body_filter(conf)
  -- if body_filter is called twice, then return
  if kong.ctx.plugin.body_called then
    return
  end

  if kong.ctx.shared.skip_response_transformer then
    local response_body

    if kong.ctx.shared.parsed_response then
      response_body = kong.ctx.shared.parsed_response

    elseif kong.response.get_status() == 200 then
      response_body = kong.service.response.get_raw_body()
      if not response_body then
        kong.log.warn("issue when retrieve the response body for analytics in the body filter phase.",
                      " Please check AI request transformer plugin response.")
      else
        local is_gzip = kong.response.get_header("Content-Encoding") == "gzip"
        if is_gzip then
          response_body = kong_utils.inflate_gzip(response_body)
        end
      end
    end

    local ai_driver = require("kong.llm.drivers." .. conf.model.provider)
    local route_type = conf.route_type
    local new_response_string, err = ai_driver.from_format(response_body, conf.model, route_type)
    
    if err then
      kong.log.warn("issue when transforming the response body for analytics in the body filter phase, ", err)

    elseif new_response_string then
      ai_shared.post_request(conf, new_response_string)
    end
  end

  if not kong.ctx.shared.skip_response_transformer then
    if (kong.response.get_status() ~= 200) and (not kong.ctx.plugin.ai_parser_error) then
      return
    end
  
    -- (kong.response.get_status() == 200) or (kong.ctx.plugin.ai_parser_error)
  
    -- all errors MUST be checked and returned in header_filter
    -- we should receive a replacement response body from the same thread

    if route_type ~= "preserve" then
      local original_request = kong.ctx.plugin.parsed_response
      local deflated_request = original_request
      
      if deflated_request then
        local is_gzip = kong.response.get_header("Content-Encoding") == "gzip"
        if is_gzip then
          deflated_request = kong_utils.deflate_gzip(deflated_request)
        end

        kong.response.set_raw_body(deflated_request)
      end

      -- call with replacement body, or original body if nothing changed
      local _, err = ai_shared.post_request(conf, original_request)
      if err then
        kong.log.warn("analytics phase failed for request, ", err)
      end
    end
  end

  kong.ctx.plugin.body_called = true
end


function _M:access(conf)
  -- store the route_type in ctx for use in response parsing
  local route_type = conf.route_type
  kong.ctx.plugin.operation = route_type

  local request_table
  local multipart = false

  -- we may have received a replacement / decorated request body from another AI plugin
  if kong.ctx.shared.replacement_request then
    kong.log.debug("replacement request body received from another AI plugin")
    request_table = kong.ctx.shared.replacement_request

  else
    -- first, calculate the coordinates of the request
    local content_type = kong.request.get_header("Content-Type") or "application/json"

    request_table = kong.request.get_body(content_type)

    if not request_table then
      if not string.find(content_type, "multipart/form-data", nil, true) then
        return bad_request("content-type header does not match request body")
      end

      multipart = true  -- this may be a large file upload, so we have to proxy it directly
    end
  end

  -- resolve the real plugin config values
  local conf_m, err = ai_shared.resolve_plugin_conf(kong.request, conf)
  if err then
    return bad_request(err)
  end

  -- copy from the user request if present
  if (not multipart) and (not conf_m.model.name) and (request_table.model) then
    conf_m.model.name = request_table.model
  elseif multipart then
    conf_m.model.name = "NOT_SPECIFIED"
  end

  -- model is stashed in the copied plugin conf, for consistency in transformation functions
  if not conf_m.model.name then
    return bad_request("model parameter not found in request, nor in gateway configuration")
  end

  -- stash for analytics later
  kong.ctx.plugin.llm_model_requested = conf_m.model.name

  -- check the incoming format is the same as the configured LLM format
  if not multipart then
    local compatible, err = llm.is_compatible(request_table, route_type)
    if not compatible then
      kong.ctx.shared.skip_response_transformer = true
      return bad_request(err)
    end
  end

  if request_table.stream or conf.model.options.response_streaming == "always" then
    kong.ctx.shared.skip_response_transformer = true

    -- into sub-request streaming handler
    -- everything happens in the access phase here
    if conf.model.options.response_streaming == "deny" then
      return bad_request("response streaming is not enabled for this LLM")
    end

    local llm_handler = ai_module:new(conf, {})
    llm_handler:handle_streaming_request(request_table)
  else
    kong.service.request.enable_buffering()

    local ai_driver = require("kong.llm.drivers." .. conf.model.provider)

    -- execute pre-request hooks for this driver
    local ok, err = ai_driver.pre_request(conf, request_table)
    if not ok then
      kong.ctx.shared.skip_response_transformer = true
      return bad_request(err)
    end

    local parsed_request_body, content_type, err
    if route_type ~= "preserve" and (not multipart) then
      -- transform the body to Kong-format for this provider/model
      parsed_request_body, content_type, err = ai_driver.to_format(request_table, conf_m.model, route_type)
      if err then
        kong.ctx.shared.skip_response_transformer = true
        return bad_request(err)
      end
    end

    -- execute pre-request hooks for "all" drivers before set new body
    local ok, err = ai_shared.pre_request(conf, parsed_request_body)
    if not ok then
      return bad_request(err)
    end

    if route_type ~= "preserve" then
      kong.service.request.set_body(parsed_request_body, content_type)
    end

    -- now re-configure the request for this operation type
    local ok, err = ai_driver.configure_request(conf)
    if not ok then
      kong.ctx.shared.skip_response_transformer = true
      return internal_server_error(err)
    end

    -- lights out, and away we go
  end
end


return _M
