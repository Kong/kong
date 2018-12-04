local codec          = require "kong.openid-connect.codec"


local sub            = string.sub
local ngx            = ngx
local var            = ngx.var
local get_headers    = ngx.req.get_headers
local clear_header   = ngx.req.clear_header
local set_header     = ngx.req.set_header
local get_uri_args   = ngx.req.get_uri_args
local set_uri_args   = ngx.req.set_uri_args
local read_body      = ngx.req.read_body
local set_body_data  = ngx.req.set_body_data
local get_post_args  = ngx.req.get_post_args
local get_body_data  = ngx.req.get_body_data
local encode_args    = ngx.encode_args
local select         = select
local ipairs         = ipairs
local lower          = string.lower
local type           = type
local null           = ngx.null
local next           = next
local json           = codec.json
local base64         = codec.base64
local nothing        = function() return nil end


local CONTENT_LENGTH = "Content-Length"


local function get_value(value)
  if value ~= nil and value ~= null and value ~= "" then
    if type(value) ~= "table" or next(value) then
      return value
    end
  end

  return nil
end


local function create_get_conf_arg(conf)
  return function(name, default)
    if not name then
      return default
    end

    local value = get_value(conf[name])

    if value == nil then
      return default
    end

    return value
  end
end


local function create_get_conf_args(get_conf_arg)
  return function(args_names, args_values)
    args_names = get_conf_arg(args_names)
    if not args_names then
      return nil
    end

    args_values = get_conf_arg(args_values)
    if not args_values then
      return nil
    end

    local args
    for i, name in ipairs(args_names) do
      if name and name ~= "" then
        if not args then
          args = {}
        end

        args[name] = args_values[i]
      end
    end

    return args
  end
end


local function create_get_headers()
  local initialized = false
  local headers

  return function()
    if not initialized then
      initialized = true
      headers = get_value(get_headers())
    end

    return headers
  end
end


local function create_get_header(hdrs)
  return function(name, prefix)
    if not name then
      return nil
    end

    local headers = hdrs()
    if not headers then
      return nil
    end

    local bearer, basic
    if name == "authorization:bearer" then
      name   = "Authorization"
      bearer = true

    elseif name == "authorization:basic" then
      name  = "Authorization"
      basic = true
    end

    local header_arg = get_value(headers[name])
    if not header_arg then
      local prefix_type = type(prefix)
      if prefix_type == "string" then
        header_arg = get_value(headers[prefix .. "-" .. name])

      elseif prefix_type == "table" then
        for _, p in ipairs(prefix) do
          header_arg = get_value(headers[p .. "-" .. name])
          if header_arg then
            break
          end
        end
      end
    end

    if type(header_arg) == "table" then
      return get_value(header_arg[1])
    end

    if header_arg then
      local value_prefix = lower(sub(header_arg, 1, 6))
      if bearer then
        if value_prefix == "bearer" then
          return sub(header_arg, 8)

        else
          return nil
        end

      elseif basic then
        if sub(value_prefix, 1, 5) == "basic" then
          header_arg = sub(header_arg, 7)
          local decoded = base64.decode(header_arg)
          if decoded then
            header_arg = decoded
          end

        else
          return nil
        end
      end
    end

    return header_arg
  end
end


local function clear_header_arg(name, prefix)
  if not name then
    return nil
  end

  clear_header(name)

  if not prefix then
    return
  end

  local prefix_type = type(prefix)
  if prefix_type == "string" then
    clear_header(prefix .. "-" .. name)

  elseif prefix_type == "table" then
    for _, p in ipairs(prefix) do
      clear_header(p .. "-" .. name)
    end
  end
end


local function create_get_arg(args)
  return function(name)
    if not name then
      return nil
    end

    local all_args = args()
    if not all_args then
      return nil
    end

    local arg = get_value(all_args[name])
    if type(arg) == "table" then
      return get_value(arg[1])
    end

    return arg
  end
end


local function create_get_uri_args()
  local initialized = false
  local uri_args

  return function()
    if not initialized then
      initialized = true
      uri_args = get_value(get_uri_args())
    end

    return uri_args
  end
end


local function create_clear_uri_arg(uargs)
  return function(...)
    local uri_args = uargs()
    if not uri_args then
      return nil
    end

    local n = select("#", ...)
    if n == 0 then
      return
    end

    for i = 1, n do
      local name = select(i, ...)
      uri_args[name] = nil
    end

    set_uri_args(uri_args)
  end
end


local function create_get_post_args(content_type)
  if sub(content_type, 1, 33) ~= "application/x-www-form-urlencoded" then
    return nothing
  end

  local initialized = false
  local post_args

  return function()
    if not initialized then
      initialized = true
      read_body()
      post_args = get_value(get_post_args())
    end

    return post_args
  end
end


local function create_clear_post_arg(pargs)
  return function(...)
    local post_args = pargs()
    if not post_args then
      return
    end

    local n = select("#", ...)
    if n == 0 then
      return
    end

    for i = 1, n do
      local name = select(i, ...)
      post_args[name] = nil
    end

    local encoded_args = encode_args(post_args)
    set_header(CONTENT_LENGTH, #encoded_args)
    set_body_data(encoded_args)
  end
end


local function create_get_json_args(content_type)
  if sub(content_type, 1, 16) ~= "application/json" then
    return nothing
  end

  local initialized = false
  local json_args

  return function()
    if not initialized then
      initialized = true
      read_body()
      local data = get_body_data()
      if not data then
        return nil
      end

      json_args = json.decode(data)
    end

    return json_args
  end
end


local function create_clear_json_arg(jargs)
  return function(...)
    local json_args = jargs()
    if not json_args then
      return
    end

    local n = select("#", ...)
    if n == 0 then
      return
    end

    for i = 1, n do
      local name = select(i, ...)
      json_args[name] = nil
    end

    local encoded_args = json.encode(json_args)
    set_header(CONTENT_LENGTH, #encoded_args)
    set_body_data(encoded_args)
  end
end


local function create_get_body_arg(get_post_arg, get_json_arg)
  return function(name)
    local arg = get_post_arg(name)
    if arg then
      return arg, "post"
    end

    arg = get_json_arg(name)
    if arg then
      return arg, "json"
    end
  end
end


local function create_get_req_arg(get_header, get_uri_arg, get_body_arg)
  return function(name, search)
    if not search then
      local arg = get_header(name, "X")
      if arg then
        return arg, "header"
      end

      arg = get_uri_arg(name)
      if arg then
        return arg, "query"
      end

      return get_body_arg(name)
    end

    for _, location in ipairs(search) do
      if location == "header" then
        local arg = get_header(name)
        if arg then
          return arg, "header"
        end

      elseif location == "query" then
        local arg = get_uri_arg(name)
        if arg then
          return arg, "query"
        end

      elseif location == "body" then
        local arg, loc = get_body_arg(name)
        if arg then
          return arg, loc
        end
      end
    end

    return nil
  end
end


return function(conf)
  local content_type = var.content_type or ""

  local conf_arg       = create_get_conf_arg(conf)
  local conf_args      = create_get_conf_args(conf_arg)
  local headers        = create_get_headers()
  local header         = create_get_header(headers)
  local uri_args       = create_get_uri_args()
  local uri_arg        = create_get_arg(uri_args)
  local clear_uri_arg  = create_clear_uri_arg(uri_args)
  local post_args      = create_get_post_args(content_type)
  local post_arg       = create_get_arg(post_args)
  local clear_post_arg = create_clear_post_arg(post_args)
  local json_args      = create_get_json_args(content_type)
  local json_arg       = create_get_arg(json_args)
  local clear_json_arg = create_clear_json_arg(json_args)
  local body_arg       = create_get_body_arg(post_arg, json_arg)
  local req_arg        = create_get_req_arg(header, uri_arg, body_arg)

  return {
    get_value      = get_value,
    get_conf_args  = conf_args,
    get_conf_arg   = conf_arg,
    get_headers    = headers,
    get_header     = header,
    clear_header   = clear_header_arg,
    get_uri_args   = uri_args,
    get_uri_arg    = uri_arg,
    clear_uri_arg  = clear_uri_arg,
    get_post_args  = post_args,
    get_post_arg   = post_arg,
    clear_post_arg = clear_post_arg,
    get_json_args  = json_args,
    get_json_arg   = json_arg,
    clear_json_arg = clear_json_arg,
    get_body_arg   = body_arg,
    get_req_arg    = req_arg,
  }
end
