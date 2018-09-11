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
  return function(name, prefix)
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
      bearer = true

    elseif name_lower == "authorization:basic" then
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
          local decoded = decode_base64(header_arg)
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


local function clear_header_arg(name, prefix)
  if not name then
    return nil
  end

  local name_lower = lower(name)
  if name_lower == "authorization:bearer" or name_lower == "authorization:basic" then
    clear_header("Authorization")
  else
    clear_header(name)
  end

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
