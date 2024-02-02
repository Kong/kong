local _M = {}

-- imports
local ai_shared = require("kong.llm.drivers.shared")
local llm = require("kong.llm")
local cjson = require("cjson.safe")
local kong_utils = require("kong.tools.gzip")
local kong_meta = require "kong.meta"
--

_M.PRIORITY = 770
_M.VERSION = kong_meta.version

local function bad_request(msg)
  kong.log.warn(msg)
  return kong.response.exit(400, { error = { message = msg } })
end

local function internal_server_error(msg)
  kong.log.err(msg)
  return kong.response.exit(500, { error = { message = msg } })
end

function _M:header_filter(conf)
  if not kong.ctx.shared.skip_response_transformer then
    -- clear shared restricted headers
    for i, v in ipairs(ai_shared.clear_response_headers.shared) do
      kong.response.clear_header(v)
    end

    -- only act on 200 in first release - pass the unmodifed response all the way through if any failure
    if kong.response.get_status() == 200 then
      local ai_driver = require("kong.llm.drivers." .. conf.model.provider)
      local route_type = conf.route_type
      
      local response_body = kong.service.response.get_raw_body()

      if response_body then
        local is_gzip = kong.response.get_header("Content-Encoding") == "gzip"

        if is_gzip then
          response_body = kong_utils.inflate_gzip(response_body)
        end

        local new_response_string, err = ai_driver.from_format(response_body, conf.model, route_type)
        if err then
          kong.ctx.plugin.ai_parser_error = true

          ngx.status = 500
          local message = {
            error = {
              message = err,
            },
          }

          kong.ctx.plugin.parsed_response = cjson.encode(message)
        
        elseif new_response_string then
          -- preserve the same response content type; assume the from_format function
          -- has returned the body in the appropriate response output format
          kong.ctx.plugin.parsed_response = new_response_string
        end

        ai_driver.post_request(conf)
      end
    end
  end
end

function _M:body_filter(conf)
  if not kong.ctx.shared.skip_response_transformer then
    if (kong.response.get_status() == 200) or (kong.ctx.plugin.ai_parser_error) then
      -- all errors MUST be checked and returned in header_filter
      -- we should receive a replacement response body from the same thread

      local original_request = kong.ctx.plugin.parsed_response
      local deflated_request = kong.ctx.plugin.parsed_response
      if deflated_request then
        local is_gzip = kong.response.get_header("Content-Encoding") == "gzip"
        if is_gzip then
          deflated_request = kong_utils.deflate_gzip(deflated_request)
        end

        kong.response.set_raw_body(deflated_request)
      end

      -- call with replacement body, or original body if nothing changed
      ai_shared.post_request(conf, original_request)
    end
  end
end

function _M:access(conf)
  kong.service.request.enable_buffering()

  -- store the route_type in ctx for use in response parsing
  local route_type = conf.route_type
  kong.ctx.plugin.operation = route_type

  local ai_driver = require("kong.llm.drivers." .. conf.model.provider)

  local request_table
  -- we may have received a replacement / decorated request body from another AI plugin
  if kong.ctx.shared.replacement_request then
    kong.log.debug("replacement request body received from another AI plugin")
    request_table = kong.ctx.shared.replacement_request
  else
    -- first, calculate the coordinates of the request
    local content_type = kong.request.get_header("Content-Type") or "application/json"

    request_table = kong.request.get_body(content_type)

    if not request_table then
      return bad_request("content-type header does not match request body")
    end
  end

  -- check the incoming format is the same as the configured LLM format
  local compatible, err = llm.is_compatible(request_table, conf.route_type)
  if not compatible then
    kong.ctx.shared.skip_response_transformer = true
    return bad_request(err)
  end

  -- execute pre-request hooks for this driver
  local ok, err = ai_driver.pre_request(conf, request_table)
  if not ok then
    return bad_request(err)
  end

  -- transform the body to Kong-format for this provider/model
  local parsed_request_body, content_type, err = ai_driver.to_format(request_table, conf.model, route_type)
  if err then
    return bad_request(err)
  end

  -- execute pre-request hooks for "all" drivers before set new body
  local ok, err = ai_shared.pre_request(conf, parsed_request_body)
  if not ok then
    return bad_request(err)
  end

  kong.service.request.set_body(parsed_request_body, content_type)

  -- now re-configure the request for this operation type
  local ok, err = ai_driver.configure_request(conf)
  if not ok then
    return internal_server_error(err)
  end
  
  -- lights out, and away we go
end

return _M
