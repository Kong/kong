-- Copyright (C) Mashape, Inc.

local stringy = require "stringy"
local cjson = require "cjson"

local _M = {}

local function get_basic_auth(header)
  local username = nil
  local password = nil

  if header then
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

    if m and table.getn(m) > 0 then
      local decoded_basic = ngx.decode_base64(m[1])
      local basic_parts = stringy.split(decoded_basic, ":")

      username = basic_parts[1]
      password = basic_parts[2]
    end
  end

  return username, password
end

local function set_new_body(request, data)
  request.set_header("content-length", string.len(data))
  request.set_body_data(data)
end

local function do_get_keys(authentication_key_name, request, api, vars, headers, hide_credentials)
  local secret_key = nil

  if authentication_key_name then
    if api.authentication_type == "header" and headers[authentication_key_name] then
      secret_key = headers[authentication_key_name]
      if hide_credentials then
        request.clear_header(authentication_key_name)
      end
    else
      -- Try to get it from the querystring
      local uri_args = request.get_uri_args()
      secret_key = uri_args[authentication_key_name]
      if secret_key and hide_credentials then
        uri_args[authentication_key_name] = nil
        vars.querystring = ngx.encode_args(uri_args)
      end
      local content_type = ngx.req.get_headers()["content-type"]
      if not secret_key and content_type then -- If missing from querystring, get it from the body
        content_type = string.lower(content_type) -- Lower it for easier comparison
        if content_type == "application/x-www-form-urlencoded" or stringy.startswith(content_type, "multipart/form-data") then
          request.read_body()
          local post_args = request.get_post_args()
          if post_args then
            secret_key = post_args[authentication_key_name]
            if hide_credentials then
              post_args[authentication_key_name] = nil
              set_new_body(request, ngx.encode_args(post_args))
            end
          end
        elseif content_type == "application/json" then
          -- Call ngx.req.read_body to read the request body first or turn on the lua_need_request_body directive to avoid errors.
          request.read_body()
          local body_data = request.get_body_data()
          if body_data and string.len(body_data) > 0 then
            local json = cjson.decode(body_data)
            secret_key = json[authentication_key_name]
            if hide_credentials then
              json[authentication_key_name] = nil
              set_new_body(request, cjson.encode(json))
            end
          end
        end
      end
    end
  end

  return nil, secret_key
end

local function get_keys(request, api, vars)
  local public_key, secret_key

  local hide_credentials = configuration.plugins.authentication.hide_credentials
  local headers = request.get_headers()

  if api.authentication_type == "basic" then
    public_key, secret_key = get_basic_auth(headers["authorization"])
    if hide_credentials then
      request.clear_header("authorization")
    end
  elseif api.authentication_key_names then
    for i, authentication_key_name in ipairs(api.authentication_key_names) do
      public_key, secret_key = do_get_keys(authentication_key_name, request, api, vars, headers, hide_credentials)
      if public_key or secret_key then break end
    end
  end

  return public_key, secret_key
end

function _M.execute()
  local api = ngx.ctx.api

  local public_key, secret_key = get_keys(ngx.req, api, ngx.var)
  local application = dao.applications:get_by_key(public_key, secret_key)
  if not application then
    utils.show_error(403, "Your authentication credentials are invalid")
  end

  ngx.req.set_header("x-account-id", application.account_id)

  ngx.ctx.authenticated_entity = application
end

return _M
