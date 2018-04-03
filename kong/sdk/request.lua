local cjson = require "cjson.safe"
local multipart = require "multipart"
local singletons = require "kong.singletons"


local ngx = ngx
local sub = string.sub
local find = string.find
local type = type
local assert = assert
local tonumber = tonumber


local function get_content_length(request)
  local content_length = request.get_header("Content-Length")
  if not content_length then
    return
  end

  if type(content_length) == "table" then
    if not content_length[1] then
      return
    end

    content_length = content_length[1]
  end

  return tonumber(content_length)
end


local function new(sdk, _SDK_REQUEST, major_version)
  -- could change in future versions
  local MAX_HEADERS = 50
  local MAX_QUERY_ARGS = 100


  function _SDK_REQUEST.get_scheme()
    --[[
    -- should probably be optional
    -- maybe part of get_protocol() instead?
    if sdk.ip.is_trusted(var.realip_remote_addr) then
      local scheme = _SDK_REQUEST.get_header("X-Forwarded-Proto")
      if type(scheme) == "table" then
        scheme = scheme[1]
      end

      if not scheme then
        scheme = var.scheme
      end

      return scheme
    end
    -- ]]

    return ngx.var.scheme
  end


  function _SDK_REQUEST.get_host()
    -- TODO: add support for Forwarded header (the non X-Forwarded one)
    --[[
    -- should probably be optional?
    local var = ngx.var
    local host
    if sdk.ip.is_trusted(var.realip_remote_addr) then
      host = _SDK_REQUEST.get_header("X-Forwarded-Host")
      if type(host) == "table" then
        host = host[1]
      end

      if not host then
        host = var.host
      end

    else
      host = var.host
    end
    --]]

    -- TODO: this should never be the case, but just in case (remove?)
    --[[
    local s = find(host, "@", 1, true)
    if s then
      host = sub(host, s + 1)
    end

    s = find(host, ":", 1, true)
    if s then
      host = sub(host, 1, s - 1)
    end
    --]]

    return ngx.var.host
  end


  function _SDK_REQUEST.get_port()
    -- TODO: add support for Forwarded header (the non-X-Forwarded one)

    --[[
    local var = ngx.var
    local port
    if singletons.ip.trusted(var.realip_remote_addr) then
      port = _SDK_REQUEST.get_header("X-Forwarded-Port")
      if type(port) == "table" then
        port = tonumber(port[1])
      end

      if not port or port < 1 or port > 65535 then
        local host = _SDK_REQUEST.get_header("X-Forwarded-Host")
        if type(host) == "table" then
          host = host[1]
        end

        if not host then
          host = var.host
        end

        -- TODO: this should never be the case, but just in case (remove?)
        local s = find(host, "@", 1, true)
        if s then
          host = sub(host, s + 1)
        end

        s = find(host, ":", 1, true)
        if s then
          port = tonumber(sub(host, s + 1))
        end
      end
    end
    --]]

    return tonumber(ngx.var.remote_port)
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

    return _SDK_REQUEST.get_headers()[header]
  end


  function _SDK_REQUEST.get_query_args(max_args)
    -- TODO: add phase and request level caches (what about max_args here?)

    if max_args == nil then
      max_args = MAX_QUERY_ARGS

    else
      assert(type(max_args) == "number", "max_args argument is not a number")
      assert(max_args > 0, "max_args argument needs to be a positive number")
    end

    return ngx.req.get_uri_args(max_args)
  end


  function _SDK_REQUEST.get_post_args(max_args)
    -- TODO: (what about max_args here?)

    if max_args == nil then
      max_args = 100

    else
      assert(type(max_args) == "number", "max_args argument is not a number")
      assert(max_args > 0, "max_args argument needs to be a positive number")
    end

    local content_length = get_content_length(_SDK_REQUEST)
    if content_length and content_length < 1 then
      return {}
    end

    -- TODO: should we also compare content_length to client_body_buffer_size here?

    ngx.req.read_body()
    return ngx.req.get_post_args(max_args)
  end


  function _SDK_REQUEST.get_body()
    local content_length = get_content_length(_SDK_REQUEST)
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

    if type(content_type) == "table" then
      content_type = content_type[1]
      if not content_type then
        return nil, "unexpected error with content type header", nil
      end
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
