local cjson = require "cjson.safe"
local multipart = require "multipart"


local ngx = ngx
local sub = string.sub
local find = string.find
local lower = string.lower
local type = type
local error = error
local tonumber = tonumber


local function new(sdk, _SDK_REQUEST, major_version)
  local MAX_HEADERS = 100
  local MAX_QUERY_ARGS = 100
  local MAX_POST_ARGS = 100

  local MIN_PORT = 1
  local MAX_PORT = 65535

  local CONTENT_LENGTH = "Content-Length"
  local CONTENT_TYPE = "Content-Type"

  local CONTENT_TYPE_POST = "application/x-www-form-urlencoded"
  local CONTENT_TYPE_JSON = "application/json"
  local CONTENT_TYPE_FORM_DATA = "multipart/form-data"

  local X_FORWARDED_PROTO = "X-Forwarded-Proto"
  local X_FORWARDED_HOST = "X-Forwarded-Host"
  local X_FORWARDED_PORT = "X-Forwarded-Port"


  function _SDK_REQUEST.get_scheme()
    return ngx.var.scheme
  end


  function _SDK_REQUEST.get_forwarded_scheme()
    if sdk.ip.is_trusted(sdk.client.get_ip()) then
      local scheme = _SDK_REQUEST.get_header(X_FORWARDED_PROTO)
      if scheme then
        return lower(scheme)
      end
    end

    return _SDK_REQUEST.get_scheme()
  end


  function _SDK_REQUEST.get_host()
    return ngx.var.host
  end


  function _SDK_REQUEST.get_forwarded_host()
    local host
    if sdk.ip.is_trusted(sdk.client.get_ip()) then
      host = _SDK_REQUEST.get_header(X_FORWARDED_HOST)
      if host then
        local s = find(host, "@", 1, true)
        if s then
          host = sub(host, s + 1)
        end

        s = find(host, ":", 1, true)
        return s and lower(sub(host, 1, s - 1)) or lower(host)
      end
    end

    return _SDK_REQUEST.get_host()
  end


  function _SDK_REQUEST.get_port()
    return tonumber(ngx.var.server_port)
  end


  function _SDK_REQUEST.get_forwarded_port()
    local port
    if sdk.ip.trusted(sdk.client.get_ip()) then
      port = tonumber(_SDK_REQUEST.get_header(X_FORWARDED_PORT))
      if port and port >= MIN_PORT and port <= MAX_PORT then
        return port
      end

      local host = _SDK_REQUEST.get_header(X_FORWARDED_HOST)
      if host then
        local s = find(host, "@", 1, true)
        if s then
          host = sub(host, s + 1)
        end

        s = find(host, ":", 1, true)
        if s then
          port = tonumber(sub(host, s + 1))

          if port and port >= MIN_PORT and port <= MAX_PORT then
            return port
          end
        end
      end
    end

    return _SDK_REQUEST.get_port()
  end


  function _SDK_REQUEST.get_path()
    local uri = ngx.var.request_uri
    local idx = find(uri, "?", 2, true)
    return idx and sub(uri, 1, idx - 1) or uri
  end


  function _SDK_REQUEST.get_query()
    return ngx.var.args
  end


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


  function _SDK_REQUEST.get_header(name)
    if type(name) ~= "string" then
      error("name must be a string", 2)
    end

    local header_value = _SDK_REQUEST.get_headers()[name]
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


  function _SDK_REQUEST.get_query_arg(name)
    if type(name) ~= "string" then
      error("name must be a string", 2)
    end

    local arg_value = _SDK_REQUEST.get_query_args()[name]
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
      end
    end

    local content_length = tonumber(_SDK_REQUEST.get_header(CONTENT_LENGTH))
    if content_length and content_length < 1 then
      return {}
    end

    -- TODO: should we also compare content_length to client_body_buffer_size here?

    ngx.req.read_body()
    return ngx.req.get_post_args(max_args)
  end


  function _SDK_REQUEST.get_post_arg(name)
    if type(name) ~= "string" then
      error("name must be a string", 2)
    end

    local arg_value = _SDK_REQUEST.get_post_args()[name]
    if type(arg_value) == "table" then
      return arg_value[1]
    end

    return arg_value
  end


  function _SDK_REQUEST.get_body()
    local content_length = tonumber(_SDK_REQUEST.get_header(CONTENT_LENGTH))
    if content_length and content_length < 1 then
      return ""
    end

    -- TODO: should we also compare content_length to client_body_buffer_size here?

    ngx.req.read_body()

    local body = ngx.req.get_body_data()
    if body == nil then
      if ngx.req.get_body_file() then
        return nil, "request body did not fit into client body buffer, consider raising 'client_body_buffer_size'"

      else
        return ""
      end
    end

    return body
  end


  function _SDK_REQUEST.get_body_args()
    local content_type = _SDK_REQUEST.get_header(CONTENT_TYPE)
    if not content_type then
      return nil, "content type header was not provided in request"
    end

    if find(content_type, CONTENT_TYPE_POST, 1, true) == 1 then
      local pargs, err = _SDK_REQUEST.get_post_args()
      if not pargs then
        return nil, "unable to retrieve request body arguments: " .. err, CONTENT_TYPE_POST
      end

      return pargs, nil, CONTENT_TYPE_POST

    elseif find(content_type, CONTENT_TYPE_JSON, 1, true) == 1 then
      local body, err = _SDK_REQUEST.get_body()
      if not body then
        return nil, err, CONTENT_TYPE_JSON
      end

      if body == "" then
        return nil, "request body is required for content type '" .. content_type .. "'", CONTENT_TYPE_JSON
      end

      -- TODO: cjson.decode_array_with_array_mt(true) (?)
      local json, err = cjson.decode(body)
      if not json then
        return nil, "unable to json decode request body: " .. err, CONTENT_TYPE_JSON
      end

      return json, nil, "application/json"

    elseif find(content_type, CONTENT_TYPE_FORM_DATA, 1, true) == 1 then
      local body, err = _SDK_REQUEST.get_body()
      if not body then
        return nil, err, CONTENT_TYPE_FORM_DATA
      end

      if body == "" then
        return {}, nil, CONTENT_TYPE_FORM_DATA
      end

      return multipart(body):get_all(), nil, CONTENT_TYPE_FORM_DATA

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
