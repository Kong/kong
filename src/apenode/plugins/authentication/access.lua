-- Copyright (C) Mashape, Inc.

local stringy = require "stringy"

local _M = {}

function _M.execute()
  local api = ngx.ctx.api

  local application_key = get_application_key(ngx.req, api)
  local application = dao.applications:get_by_key(application_key)
  if not dao.applications:is_valid(application, api) then
    utils.show_error(403, "Your authentication credentials are invalid")
  end

  ngx.ctx.authenticated_entity = application
end

function get_application_key(request, api)
  -- Let's check if the credential is in a request parameter
  if api.authentication_key_names then
    for i, authentication_key_name in ipairs(api.authentication_key_names) do
      local application_key = do_get_application_key(authentication_key_name, request, api)
      if application_key then return application_key end
    end
  end

  return nil
end

function do_get_application_key(authentication_key_name, request, api)
  local application_key = nil

  if authentication_key_name then
    -- Try to get it from the querystring
    application_key = request.get_uri_args()[authentication_key_name]
    local content_type = ngx.req.get_headers()["content-type"]
    if not application_key and content_type then -- If missing from querystring, get it from the body
      content_type = string.lower(content_type) -- Lower it for easier comparison
      if content_type == "application/x-www-form-urlencoded" or stringy.startswith(content_type, "multipart/form-data") then
        request.read_body()
        local post_args = request.get_post_args()
        if post_args then
          application_key = post_args[authentication_key_name]
        end
      elseif content_type == "application/json" then
        -- Call ngx.req.read_body to read the request body first or turn on the lua_need_request_body directive to avoid errors.
        request.read_body()
        local body_data = request.get_body_data()
        if body_data and string.len(body_data) > 0 then
          local json = cjson.decode(body_data)
          application_key = json[authentication_key_name]
        end
      end
    end
  end

  -- The credentials might also be in the header
  if not application_key and api.authentication_header_name then
    application_key = request.get_headers()[api.authentication_header_name]
  end

  return application_key
end

return _M
