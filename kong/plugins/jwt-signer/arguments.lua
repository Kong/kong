local sub           = string.sub
local ngx           = ngx
local get_headers   = ngx.req.get_headers
local clear_header  = ngx.req.clear_header
local set_header    = ngx.req.set_header
local ipairs        = ipairs
local lower         = string.lower
local type          = type
local null          = ngx.null
local next          = next
local decode_base64 = ngx.decode_base64


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
  return function(name)
    if not name then
      return nil
    end

    local headers = hdrs()
    if not headers then
      return nil
    end

    local bearer, basic
    local name_lower = lower(name)
    if name_lower == "authorization:bearer" then
      name   = "Authorization"

    elseif name_lower == "authorization:basic" then
      name  = "Authorization"
    end

    local header_arg = get_value(headers[name])
    if type(header_arg) == "table" then
      return get_value(header_arg[1])
    end

    return header_arg
  end
end


local function set_header_arg(name, value)
  if not name then
    return nil
  end

  local name_lower = lower(name)
  if name_lower == "authorization:bearer" then
    set_header("Authorization", "Bearer " .. value)
  elseif name_lower == "authorization:basic" then
    set_header("Authorization", "Basic " .. value)
  else
    set_header(name, value)
  end
end


local function clear_header_arg(name)
  if not name then
    return nil
  end

  local name_lower = lower(name)
  if name_lower == "authorization:bearer" or name_lower == "authorization:basic" then
    clear_header("Authorization")
  else
    clear_header(name)
  end
end


return function(conf)
  local conf_arg  = create_get_conf_arg(conf)
  local headers   = create_get_headers()
  local header    = create_get_header(headers)

  return {
    get_value     = get_value,
    get_conf_arg  = conf_arg,
    get_headers   = headers,
    get_header    = header,
    set_header    = set_header_arg,
    clear_header  = clear_header_arg,
  }
end
