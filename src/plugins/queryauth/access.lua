local constants = require "kong.constants"
local stringy = require "stringy"
local cjson = require "cjson"
local cache = require "kong.tools.cache"

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
--
-- @param request ngx request object
-- @param {table} conf Plugin configuration (value property)
-- @return {string} public_key
-- @return {string} private_key
local function retrieve_credentials(request, conf)
  local public_key

  if conf.key_names then
    for _,key_name in ipairs(conf.key_names) do
      public_key = get_key_from_query(key_name, request, conf)

      if public_key then
        return public_key
      end

    end
  end
end

-- Fast lookup for credential validation depending on the type of the authentication
--
-- All methods must respect:
--
-- @param {table} application The retrieved application from the public_key passed in the request
-- @param {string} public_key
-- @param {string} private_key
-- @return {boolean} Success of authentication
local function validate_credentials(application, public_key)
  return application ~= nil
end

function _M.execute(conf)
  if not conf then return end

  local public_key, secret_key = retrieve_credentials(ngx.req, conf)
  local application

  -- Make sure we are not sending an empty table to find_by_keys
  if public_key then
    application = cache.get_and_set(cache.application_key(public_key), function()
      local applications, err = dao.applications:find_by_keys { public_key = public_key }
      local result
      if err then
        ngx.log(ngx.ERR, err)
        utils.show_error(500)
      elseif #applications > 0 then
        result = applications[1]
      end
      return result
    end)
  end

  if not validate_credentials(application, public_key, secret_key) then
    utils.show_error(403, "Your authentication credentials are invalid")
  end

  ngx.req.set_header(constants.HEADERS.ACCOUNT_ID, application.account_id)
  ngx.ctx.authenticated_entity = application
end

return _M
