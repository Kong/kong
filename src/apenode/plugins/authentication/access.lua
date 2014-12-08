-- Copyright (C) Mashape, Inc.

local stringy = require "stringy"

local _M = {}

local function get_keys(request, api)
  -- Let's check if the credential is in a request parameter
  if api.authentication_key_names then
    for i, authentication_key_name in ipairs(api.authentication_key_names) do
      local public_key, secret_key = do_get_keys(authentication_key_name, request, api)
      if public_key or secret_key then return public_key, secret_key end
    end
  end

  return nil, nil
end

local function do_get_keys(authentication_key_name, request, api)
  local secret_key = nil

  local headers = request.get_headers()

  if authentication_key_name then
    if headers[authentication_key_name] then
      secret_key = headers[authentication_key_name]
    else
      -- Try to get it from the querystring
      secret_key = request.get_uri_args()[authentication_key_name]
      local content_type = ngx.req.get_headers()["content-type"]
      if not secret_key and content_type then -- If missing from querystring, get it from the body
        content_type = string.lower(content_type) -- Lower it for easier comparison
        if content_type == "application/x-www-form-urlencoded" or stringy.startswith(content_type, "multipart/form-data") then
          request.read_body()
          local post_args = request.get_post_args()
          if post_args then
            secret_key = post_args[authentication_key_name]
          end
        elseif content_type == "application/json" then
          -- Call ngx.req.read_body to read the request body first or turn on the lua_need_request_body directive to avoid errors.
          request.read_body()
          local body_data = request.get_body_data()
          if body_data and string.len(body_data) > 0 then
            local json = cjson.decode(body_data)
            secret_key = json[authentication_key_name]
          end
        end
      end
    end
  end

  if api.authentication_type == "basic" then
    return get_basic_auth(secret_key)
  else
    return nil, secret_key
  end
end

local function get_basic_auth(header)
  local iterator, err = ngx.re.gmatch(header, "\\s*[Bb]asic\\s*(.+)")
  if not iterator then
      ngx.log(ngx.ERR, "error: ", err)
      return
  end

  local m, err = iterator()
  if err then
      ngx.log(ngx.ERR, "error: ", err)
      return
  end

  local decoded_basic = ngx.decode_base64(m[1])
  local basic_parts = stringy.split(decoded_basic, ":")

  local username = basic_parts[1]
  local password = basic_parts[2]

  if stringy.strip(username) == "" then username = nil end
  if stringy.strip(password) == "" then password = nil end

  return username, password
end

function _M.execute()
  local api = ngx.ctx.api

  local public_key, secret_key = get_keys(ngx.req, api)
  local application = dao.applications:get_by_key(public_key, secret_key)
  if not dao.applications:is_valid(application, api) then
    utils.show_error(403, "Your authentication credentials are invalid")
  end

  ngx.ctx.authenticated_entity = application
end

return _M
