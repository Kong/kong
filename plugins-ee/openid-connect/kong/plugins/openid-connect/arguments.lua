-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local json           = require "cjson.safe"


local kong           = kong
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
local concat         = table.concat
local lower          = string.lower
local find           = string.find
local gsub           = string.gsub
local sub            = string.sub
local type           = type
local null           = ngx.null
local next           = next
local decode_base64  = ngx.decode_base64
local nothing        = function() return nil end


local CONTENT_TYPE   = "Content-Type"
local CONTENT_LENGTH = "Content-Length"
local PARAM_TYPES_ALL = {
  "header",
  "query",
  "body",
}


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


local function create_get_headers(hdrs)
  if hdrs then
    return function()
      return hdrs
    end
  end

  local initialized = false
  local headers, err

  return function()
    if not initialized then
      initialized = true
      headers, err = get_headers()
      headers = get_value(headers)
    end

    return headers, err
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

    local bearer, dpop, basic
    if name == "authorization:bearer" then
      name   = "Authorization"
      bearer = true

    elseif name == "authorization:dpop" then
      name  = "Authorization"
      dpop = true

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

    if not header_arg then
      return nil
    end

    if not basic and not bearer and not dpop then
      if type(header_arg) == "table" then
        return get_value(header_arg[1])
      else
        return header_arg
      end
    end

    header_arg = type(header_arg) == "table" and header_arg or { header_arg }
    for _, header in ipairs(header_arg) do
      local token_type, remaining = header:match("^(%S+)%s(.+)")
      token_type = lower(token_type or "")

      if bearer and token_type == "bearer" then
        return remaining

      elseif dpop and token_type == "dpop" then
        return remaining

      elseif basic and token_type == "basic"  then
        local decoded = decode_base64(remaining)
        if decoded then
          return decoded
        else
          return remaining
        end
      end
    end

    return nil
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
    all_args = get_value(all_args)
    if type(all_args) ~= "table" then
      return nil
    end

    local arg = get_value(all_args[name])
    if type(arg) == "table" then
      return get_value(arg[1])
    end

    return arg
  end
end


local function create_get_uri_args(uargs)
  if uargs then
    return function()
      return uargs
    end
  end

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


local function create_get_post_args(content_type, pargs)
  if sub(content_type, 1, 33) ~= "application/x-www-form-urlencoded" then
    return nothing
  end

  if pargs then
    return function()
      return pargs
    end
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


local function create_get_json_args(content_type, jargs)
  if jargs then
    return function()
      return jargs
    end
  end

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


local function is_named_cookie(cookie, name)
    if not cookie or cookie == "" then
        return false, nil
    end

    cookie = gsub(cookie, "^%s+", "")
    if cookie == "" then
        return false, nil
    end

    cookie = gsub(cookie, "%s+$", "")
    if cookie == "" then
        return false, nil
    end

    local eq_pos = find(cookie, "=", 1, true)
    if not eq_pos then
        return false, cookie
    end

    local cookie_name = sub(cookie, 1, eq_pos - 1)
    if cookie_name == "" then
        return false, cookie
    end

    cookie_name = gsub(cookie_name, "%s+$", "")
    if cookie_name == "" then
        return false, cookie
    end

    if cookie_name ~= name then
      return false, cookie
    end

    return true, cookie
end


local function clear_cookie(name, cookies)
  cookies = cookies or var.http_cookie
  if not cookies or cookies == "" then
      return
  end

  local results = {}
  local found
  local i = 1
  local j = 0
  local sc_pos = find(cookies, ";", i, true)
  while sc_pos do
      local is_named, cookie = is_named_cookie(sub(cookies, i, sc_pos - 1), name)
      if is_named then
          found = true
      elseif cookie then
          j = j + 1
          results[j] = cookie
      end

      i = sc_pos + 1
      sc_pos = find(cookies, ";", i, true)
  end

  local is_named, cookie
  if i == 1 then
      is_named, cookie = is_named_cookie(cookies, name)
  else
      is_named, cookie = is_named_cookie(sub(cookies, i), name)
  end

  if not is_named and cookie then
      if not found then
          return
      end

      j = j + 1
      results[j] = cookie
  end

  if j == 0 then
      clear_header("Cookie")
  else
      set_header("Cookie", concat(results, "; ", 1, j))
  end
end


local function create_get_http_opts(get_conf_arg)
  local initialized
  local http_version
  local http_proxy
  local http_proxy_authorization
  local https_proxy
  local https_proxy_authorization
  local no_proxy
  local keepalive
  local ssl_verify
  local timeout
  return function(options)
    if not initialized then
      http_version              = get_conf_arg("http_version", 1.1)
      http_proxy                = get_conf_arg("http_proxy")
      http_proxy_authorization  = get_conf_arg("http_proxy_authorization")
      https_proxy               = get_conf_arg("https_proxy")
      https_proxy_authorization = get_conf_arg("https_proxy_authorization")
      no_proxy                  = get_conf_arg("no_proxy")
      keepalive                 = get_conf_arg("keepalive", true)
      ssl_verify                = get_conf_arg("ssl_verify", true)
      timeout                   = get_conf_arg("timeout", 10000)
      initialized               = true
    end

    options = options or {}
    options.http_version              = http_version
    options.http_proxy                = http_proxy
    options.http_proxy_authorization  = http_proxy_authorization
    options.https_proxy               = https_proxy
    options.https_proxy_authorization = https_proxy_authorization
    options.no_proxy                  = no_proxy
    options.keepalive                 = keepalive
    options.ssl_verify                = ssl_verify
    options.timeout                   = timeout
    return options
  end
end


local function decode_basic_auth(basic_auth)
  if not basic_auth then
    return nil
  end

  local s = find(basic_auth, ":", 2, true)
  if s then
    local username = sub(basic_auth, 1, s - 1)
    local password = sub(basic_auth, s + 1)
    return username, password
  end
end


local function create_get_credentials(get_conf_arg, get_header, get_uri_arg, get_body_arg)
  return function(credential_type, usr_arg, pwd_arg)
    local password_param_type = get_conf_arg(credential_type .. "_param_type", PARAM_TYPES_ALL)
    for _, location in ipairs(password_param_type) do
      if pwd_arg then
        if location == "header" then
          local grant_type = get_header("Grant-Type", "X")
          if not grant_type or grant_type == credential_type then
            local username, password = decode_basic_auth(get_header("authorization:basic"))
            if username and password then
              return username, password, "header"
            end
          end

        elseif location == "query" then
          local grant_type = get_uri_arg("grant_type")
          if not grant_type or grant_type == credential_type then
            local username = get_uri_arg(usr_arg)
            local password = get_uri_arg(pwd_arg)
            if username and password then
              return username, password, "query"
            end
          end

        elseif location == "body" then
          local grant_type = get_body_arg("grant_type")
          if not grant_type or grant_type == credential_type then
            local username, loc = get_body_arg(usr_arg)
            local password = get_body_arg(pwd_arg)
            if username and password then
              return username, password, loc
            end
          end
        end

      else
        if location == "header" then
          local assertion = get_header(usr_arg, "X")
          if assertion then
            return assertion, nil, "header"
          end

        elseif location == "query" then
          local grant_type = get_uri_arg("grant_type")
          if not grant_type or grant_type == credential_type then
            local assertion = get_uri_arg(usr_arg)
            if assertion then
              return assertion, "query"
            end
          end
        elseif location == "body" then
          local grant_type = get_body_arg("grant_type")
          if not grant_type or grant_type == credential_type then
            local assertion, loc = get_body_arg(usr_arg)
            if assertion then
              return assertion, nil, loc
            end
          end
        end
      end
    end
  end
end


local function create_get_param_types(get_conf_arg)
  return function(name, default)
    return get_conf_arg(name, default or PARAM_TYPES_ALL)
  end
end


local function create_get_auth_methods(get_conf_arg)
  local ret
  return function()
    if not ret then
      local auth_methods = get_conf_arg("auth_methods", {
        "password",
        "client_credentials",
        "authorization_code",
        "bearer",
        "introspection",
        "userinfo",
        "kong_oauth2",
        "refresh_token",
        "session",
      })

      ret = {}
      for _, auth_method in ipairs(auth_methods) do
        ret[auth_method] = true
      end
    end

    return ret
  end
end


local function get_redirect_uri()
  local scheme = kong.request.get_forwarded_scheme()
  local host   = kong.request.get_forwarded_host()
  local port   = kong.request.get_forwarded_port()
  local path   = kong.request.get_forwarded_path()

  if (port == 80  and scheme == "http")
  or (port == 443 and scheme == "https")
  then
    return scheme .. "://" .. host .. path
  end

  return scheme .. "://" .. host .. ":" .. port .. path
end


return function(conf, hdrs, uargs, pargs, jargs)
  local content_type
  if hdrs then
    content_type = hdrs[CONTENT_TYPE]
  else
    content_type = var.content_type
  end

  if not content_type then
    content_type = ""
  end

  local conf_arg       = create_get_conf_arg(conf)
  local conf_args      = create_get_conf_args(conf_arg)
  local headers        = create_get_headers(hdrs)
  local header         = create_get_header(headers)
  local uri_args       = create_get_uri_args(uargs)
  local uri_arg        = create_get_arg(uri_args)
  local clear_uri_arg  = create_clear_uri_arg(uri_args)
  local post_args      = create_get_post_args(content_type, pargs)
  local post_arg       = create_get_arg(post_args)
  local clear_post_arg = create_clear_post_arg(post_args)
  local json_args      = create_get_json_args(content_type, jargs)
  local json_arg       = create_get_arg(json_args)
  local clear_json_arg = create_clear_json_arg(json_args)
  local body_arg       = create_get_body_arg(post_arg, json_arg)
  local req_arg        = create_get_req_arg(header, uri_arg, body_arg)
  local http_opts      = create_get_http_opts(conf_arg)
  local credentials    = create_get_credentials(conf_arg, header, uri_arg, body_arg)
  local param_types    = create_get_param_types(conf_arg)
  local auth_methods   = create_get_auth_methods(conf_arg)

  return {
    get_value        = get_value,
    get_conf_args    = conf_args,
    get_conf_arg     = conf_arg,
    get_headers      = headers,
    get_header       = header,
    clear_header     = clear_header_arg,
    set_uri_args     = set_uri_args,
    get_uri_args     = uri_args,
    get_uri_arg      = uri_arg,
    clear_uri_arg    = clear_uri_arg,
    get_post_args    = post_args,
    get_post_arg     = post_arg,
    clear_post_arg   = clear_post_arg,
    get_json_args    = json_args,
    get_json_arg     = json_arg,
    clear_json_arg   = clear_json_arg,
    get_body_arg     = body_arg,
    get_req_arg      = req_arg,
    clear_cookie     = clear_cookie,
    get_http_opts    = http_opts,
    get_credentials  = credentials,
    get_param_types  = param_types,
    get_auth_methods = auth_methods,
    get_redirect_uri = get_redirect_uri,
  }
end
