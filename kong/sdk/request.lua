local cjson = require "cjson.safe"
local multipart = require "multipart"


local ngx = ngx
local sub = string.sub
local find = string.find
local type = type
local error = error
local tonumber = tonumber


local function new(sdk, _SDK_REQUEST, major_version)
  local MAX_HEADERS = 100
  local MAX_QUERY_ARGS = 100
  local MAX_POST_ARGS = 100


  function _SDK_REQUEST.get_scheme()
    return ngx.var.scheme
  end


  --[[
  function _SDK_REQUEST.get_real_scheme()
    -- should probably be optional
    -- maybe part of get_protocol() instead?
    if sdk.ip.is_trusted(var.realip_remote_addr) then
      local scheme = _SDK_REQUEST.get_header("X-Forwarded-Proto")
      if scheme then
        return scheme
      end
    end

    return _SDK_REQUEST.get_scheme()
  end
  -- ]]


  function _SDK_REQUEST.get_username()
    return ngx.var.remote_user
  end


  function _SDK_REQUEST.get_host()
    return ngx.var.host
  end


  --[[
  function _SDK_REQUEST.get_real_host()
    -- TODO: add support for Forwarded header (the non X-Forwarded one)
    local var = ngx.var
    local host
    if sdk.ip.is_trusted(var.realip_remote_addr) then
      host = _SDK_REQUEST.get_header("X-Forwarded-Host")
      if host then
        local s = find(host, "@", 1, true)
        if s then
          host = sub(host, s + 1)
        end

        s = find(host, ":", 1, true)
        if s then
          host = sub(host, 1, s - 1)
        end

        return host
      end
    end

    return _SDK_REQUEST.get_host()
  end
  --]]


  function _SDK_REQUEST.get_port()
    return tonumber(ngx.var.server_port)
  end


  --[[
  function _SDK_REQUEST.get_real_port()
    -- TODO: add support for Forwarded header (the non-X-Forwarded one)
    local port
    if sdk.ip.trusted(var.realip_remote_addr) then
      port = tonumber(_SDK_REQUEST.get_header("X-Forwarded-Port"))
      if port and port > 0 and port < 65536 then
        return port
      end

      local host = _SDK_REQUEST.get_header("X-Forwarded-Host")
      if host then
        local s = find(host, "@", 1, true)
        if s then
          host = sub(host, s + 1)
        end

        s = find(host, ":", 1, true)
        if s then
          port = tonumber(sub(host, s + 1))

          if port and port > 0 and port < 65536 then
            return port
          end
        end
      end
    end

    return _SDK_REQUEST.get_port()
  end
  --]]


  function _SDK_REQUEST.get_method()
    return ngx.req.get_method()
  end


  function _SDK_REQUEST.get_http_version()
    return ngx.req.http_version()
  end


  function _SDK_REQUEST.get_headers(max_headers)
    if max_headers == nil then
      max_headers = MAX_HEADERS

    else
      if type(max_headers) ~= "number" then
        error("max_headers must be a number", 2)
      end

      if max_headers < 0 then
        error("max_headers must be >= 0", 2)
      end
    end

    return ngx.req.get_headers(max_headers)
  end


  function _SDK_REQUEST.get_header(header)
    if type(header) ~= "string" then
      error("header must be a string", 2)
    end

    local header_value = _SDK_REQUEST.get_headers()[header]
    if type(header_value) == "table" then
      return header_value[1]
    end

    return header_value
  end


  function _SDK_REQUEST.get_query_args(max_args)
    if max_args == nil then
      max_args = MAX_QUERY_ARGS

    else
      if type(max_args) ~= "number" then
        error("max_args must be a number", 2)
      end

      if max_args < 0 then
        error("max_args must be >= 0", 2)
      end
    end

    return ngx.req.get_uri_args(max_args)
  end


  function _SDK_REQUEST.get_query_arg(arg)
    if type(arg) ~= "string" then
      error("arg must be a string", 2)
    end

    local arg_value = _SDK_REQUEST.get_query_args()[arg]
    if type(arg_value) == "table" then
      return arg_value[1]
    end

    return arg_value
  end


  function _SDK_REQUEST.get_post_args(max_args)
    if max_args == nil then
      max_args = MAX_POST_ARGS

    else
      if type(max_args) ~= "number" then
        error("max_args must be a number", 2)
      end

      if max_args < 0 then
        error("max_args must be >= 0", 2)
      end    end

    local content_length = tonumber(_SDK_REQUEST.get_header("Content-Length"))
    if content_length and content_length < 1 then
      return {}
    end

    -- TODO: should we also compare content_length to client_body_buffer_size here?

    ngx.req.read_body()
    return ngx.req.get_post_args(max_args)
  end


  function _SDK_REQUEST.get_post_arg(arg)
    if type(arg) ~= "string" then
      error("arg must be a string", 2)
    end

    local arg_value = _SDK_REQUEST.get_post_args()[arg]
    if type(arg_value) == "table" then
      return arg_value[1]
    end

    return arg_value
  end


  function _SDK_REQUEST.get_body()
    local content_length = tonumber(_SDK_REQUEST.get_header("Content-Length"))
    if content_length and content_length < 1 then
      return "", nil
    end

    -- TODO: should we also compare content_length to client_body_buffer_size here?

    ngx.req.read_body()

    local body = ngx.req.get_body_data()
    if body == nil then
      if ngx.req.get_body_file() then
        return nil, "request body did not fit into client body buffer, consider raising 'client_body_buffer_size'"

      else
        return "", nil
      end
    end

    return body, nil
  end


  function _SDK_REQUEST.get_body_args()
    local content_type = _SDK_REQUEST.get_header("Content-Type")
    if not content_type then
      return nil, "content type header was not provided in request", nil
    end

    if find(content_type, "application/x-www-form-urlencoded", 1, true) == 1 then
      local pargs, err = _SDK_REQUEST.get_post_args()
      if not pargs then
        return nil, "unable to retrieve request body arguments: " .. err, "application/x-www-form-urlencoded"
      end

      return pargs, nil, "application/x-www-form-urlencoded"

    elseif find(content_type, "application/json", 1, true) == 1 then
      local body, err = _SDK_REQUEST.get_body()
      if not body then
        return nil, err, "application/json"
      end

      if body == "" then
        return nil, "request body is required for content type '" .. content_type .. "'", "application/json"
      end

      -- TODO: cjson.decode_array_with_array_mt(true) (?)
      local json, err = cjson.decode(body)
      if not json then
        return nil, "unable to json decode request body: " .. err, "application/json"
      end

      return json, nil, "application/json"

    elseif find(content_type, "multipart/form-data", 1, true) == 1 then
      local body, err = _SDK_REQUEST.get_body()
      if not body then
        return nil, err, "multipart/form-data"
      end

      if body == "" then
        return {}, nil, "multipart/form-data"
      end

      return multipart(body):get_all(), nil, "multipart/form-data"

    else
      local mime_type = content_type

      local s = find(mime_type, ";", 1, true)
      if s then
        mime_type = sub(mime_type, 1, s - 1)
      end

      return nil, "unsupported content type '" .. content_type .. "' was provided", mime_type
    end
  end
end


return {
  namespace = "request",
  new = new,
}
