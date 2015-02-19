local constants = require "kong.constants"
local stringy = require "stringy"
local cjson = require "cjson"

local _M = {}

local function get_key_from_query(key_name, request, conf)
  local public_key, parameters
  local found_in = {}

  -- First, try with querystring
  parameters = request.get_uri_args()

  if parameters[key_name] ~= nil then
    found_in.querystring = true
  -- If missing from querystring, try to get it from the body
  elseif request.get_headers()["content-type"] then
    -- Lowercase content-type for easier comparison
    local content_type = string.lower(request.get_headers()["content-type"])

    -- Call ngx.req.read_body to read the request body first
    -- or turn on the lua_need_request_body directive to avoid errors.
    request.read_body()

    if content_type == "application/x-www-form-urlencoded" or stringy.startswith(content_type, "multipart/form-data") then
      parameters = request.get_post_args()
      found_in.post = parameters[key_name] ~= nil
    elseif content_type == "application/json" then
      parameters = request.get_body_data()
      if parameters and string.len(parameters) > 0 then
        parameters = cjson.decode(parameters)
        found_in.body = parameters[key_name] ~= nil
      end
    end
  end

  -- At this point, we know where the key is supposed to be
  public_key = parameters[key_name]

  if conf.hide_credentials then
    if found_in.querystring then
      parameters[key_name] = nil
      ngx.vars.querystring = ngx.encode_args(parameters)
    elseif found_in.post then
      parameters[key_name] = nil
      request.set_header("content-length", string.len(parameters))
      request.set_body_data(parameters)
    elseif found_in.body then
      parameters[key_name] = nil
      parameters = cjson.encode(parameters)
      request.set_header("content-length", string.len(parameters))
      request.set_body_data(parameters)
    end
  end

  return public_key
end

-- Fast lookup for credential retrieval depending on the type of the authentication
--
-- All methods must respect:

-- @param request ngx request object
-- @param {table} conf Plugin configuration (value property)
-- @return {string} public_key
-- @return {string} private_key
local retrieve_credentials = {
  header = function(request, conf)
    local public_key
    local headers = request.get_headers()

    if conf.authentication_key_names then
      for _,key_name in ipairs(conf.authentication_key_names) do
        if headers[key_name] ~= nil then
          public_key = headers[key_name]

          if conf.hide_credentials then
            request.clear_header(key_name)
          end

          return public_key
        end
      end
    end
  end,
  query = function(request, conf)
    local public_key

    if conf.authentication_key_names then
      for _,key_name in ipairs(conf.authentication_key_names) do
        public_key = get_key_from_query(key_name, request, conf)

        if public_key then
          return public_key
        end

      end
    end
  end,
  basic = function(request, conf)
    local username, password
    local authorization_header = request.get_headers()["authorization"]

    if authorization_header then
      local iterator, err = ngx.re.gmatch(authorization_header, "\\s*[Bb]asic\\s*(.+)")
      if not iterator then
        ngx.log(ngx.ERR, err)
        return
      end

      local m, err = iterator()
      if err then
        ngx.log(ngx.ERR, err)
        return
      end

      if m and table.getn(m) > 0 then
        local decoded_basic = ngx.decode_base64(m[1])
        local basic_parts = stringy.split(decoded_basic, ":")
        username = basic_parts[1]
        password = basic_parts[2]
      end
    end

    if hide_credentials then
      request.clear_header("authorization")
    end

    return username, password
  end
}

-- Fast lookup for credential validation depending on the type of the authentication
--
-- All methods must respect:

-- @param {table} application The retrieved application from the public_key passed in the request
-- @param {string} public_key
-- @param {string} private_key
-- @return {boolean} Success of authentication
local validate_credentials = {
  header = function(application, public_key)
    return application ~= nil
  end,
  query = function(application, public_key)
    return application ~= nil
  end,
  basic = function(application, username, password)
    if application then
      -- TODO: No encryption yet
      return application.secret_key == password
    end
  end
}

function _M.execute(conf)
  if not conf then return end

  local public_key, secret_key = retrieve_credentials[conf.authentication_type](ngx.req, conf)
  local application

  -- Make sure we are not sending an empty table to find_by_keys
  if public_key then
    local applications, err = dao.applications:find_by_keys { public_key = public_key }
    if err then
      ngx.log(ngx.ERR, err)
      return
    elseif #applications > 0 then
      application = applications[1]
    end
  end

  if not validate_credentials[conf.authentication_type](application, public_key, secret_key) then
    utils.show_error(403, "Your authentication credentials are invalid")
  end

  ngx.req.set_header(constants.HEADERS.ACCOUNT_ID, application.account_id)
  ngx.ctx.authenticated_entity = application
end

return _M
