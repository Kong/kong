local constants = require "kong.constants"
local stringy = require "stringy"
local cjson = require "cjson"
local cache = require "kong.tools.cache"

local _M = {}

local function get_key_from_query(key_name, request, conf)
  local key, parameters
  local found_in = {}

  -- First, try with querystring
  parameters = request.get_uri_args()

  if parameters[key_name] ~= nil then
    found_in.querystring = true
  -- If missing from querystring, try to get it from the body
  elseif request.get_headers()["content-type"] then
    -- Lowercase content-type for easier comparison
    local content_type = stringy.strip(string.lower(request.get_headers()["content-type"]))

    if utils.starts_with(content_type, "application/x-www-form-urlencoded") or utils.starts_with(content_type, "multipart/form-data") then
      -- Call ngx.req.read_body to read the request body first
      -- or turn on the lua_need_request_body directive to avoid errors.
      request.read_body()

      print("HERE")

      parameters = request.get_post_args()
      found_in.form = parameters[key_name] ~= nil
    end
  end

  -- At this point, we know where the key is supposed to be
  key = parameters[key_name]

  if conf.hide_credentials then
    if found_in.querystring then
      parameters[key_name] = nil
      request.set_uri_args(parameters)
    elseif found_in.form or found_in.body then
      parameters[key_name] = nil

      local encoded_params = ngx.encode_args(parameters)
      request.set_header("content-length", string.len(encoded_params))
      request.set_body_data(encoded_params)
    end
  end

  return key
end

-- Fast lookup for credential retrieval depending on the type of the authentication
--
-- All methods must respect:
--
-- @param request ngx request object
-- @param {table} conf Plugin configuration (value property)
-- @return {string} public_key
-- @return {string} private_key
local retrieve_credentials = {
  [constants.AUTHENTICATION.HEADER] = function(request, conf)
    local key
    local headers = request.get_headers()

    if conf.key_names then
      for _,key_name in ipairs(conf.key_names) do
        if headers[key_name] ~= nil then
          key = headers[key_name]

          if conf.hide_credentials then
            request.clear_header(key_name)
          end

          return key
        end
      end
    end
  end,
  [constants.AUTHENTICATION.QUERY] = function(request, conf)
    local key

    if conf.key_names then
      for _,key_name in ipairs(conf.key_names) do
        key = get_key_from_query(key_name, request, conf)

        if key then
          return key
        end

      end
    end
  end
}

function _M.execute(conf)

  print("WOT")

  if not conf then return end

  local credential
  for _, v in ipairs({ constants.AUTHENTICATION.QUERY, constants.AUTHENTICATION.HEADER }) do
    local key = retrieve_credentials[v](ngx.req, conf)

    -- Make sure we are not sending an empty table to find_by_keys
    if key then
      credential = cache.get_and_set(cache.keyauth_credential_key(key), function()
        local credentials, err = dao.keyauth_credentials:find_by_keys { key = key }
        local result
        if err then
          ngx.log(ngx.ERR, tostring(err))
          utils.show_error(500)
        elseif #credentials > 0 then
          result = credentials[1]
        end
        return result
      end)
    end

    if credential then break end
  end

  if not credential then
    utils.show_error(403, "Your authentication credentials are invalid")
  end

  ngx.req.set_header(constants.HEADERS.CONSUMER_ID, credential.consumer_id)
  ngx.ctx.authenticated_entity = credential
end

return _M