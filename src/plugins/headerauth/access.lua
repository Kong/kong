local constants = require "kong.constants"
local stringy = require "stringy"
local cjson = require "cjson"
local cache = require "kong.tools.cache"

local _M = {}

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
  local headers = request.get_headers()

  if conf.header_names then
    for _,key_name in ipairs(conf.header_names) do
      if headers[key_name] ~= nil then
        public_key = headers[key_name]

        if conf.hide_credentials then
          request.clear_header(key_name)
        end

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
