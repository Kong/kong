local jwt = require "luajwt"
local cache = require "kong.tools.database_cache"
local responses = require "kong.tools.responses"
local constants = require "kong.constants"

local _M = {}

--- Retrieve a JWT in a request.
-- Checks for the JWT in URI parameters, then in the `Authorization` header.
-- @param request ngx request object
-- @param conf Plugin configuration
-- @return token JWT token contained in request or nil
local function retrieve_token(request, conf)
  local uri_parameters = request.get_uri_args()

  for _, v in ipairs(conf.uri_param_names) do
    if uri_parameters[v] then
      return uri_parameters[v]
    end
  end

  local authorization_header = request.get_headers()["authorization"]
  if authorization_header then
    local iterator, iter_err = ngx.re.gmatch(authorization_header, "\\s*[Bb]earer\\s*(.+)")
    if not iterator then
      ngx.log(ngx.ERR, "[jwt]"..iter_err)
      return
    end

    local m, err = iterator()
    if err then
      ngx.log(ngx.ERR, "[jwt]"..err)
      return
    end

    if m and table.getn(m) > 0 then
      return m[1]
    end
  end
end

local function jwt_secret_cache_key(consumer_id)
  return "jwt_secret/"..consumer_id
end

function _M.execute(conf)
  local token = retrieve_token(ngx.req, conf)

  if not token then
    ngx.ctx.stop_phases = true
    return responses.send_HTTP_UNAUTHORIZED("No JWT found in querystring or headers")
  end

  -- Decode token to fins out who the consumer is
  local claims, err = jwt.decode(token)
  if err then
    ngx.log(ngx.ERR, "[jwt]"..err)
    ngx.ctx.stop_phases = true
    return responses.send_HTTP_INTERNAL_SERVER_ERROR("Error while decoding JWT")
  end

  local secret_username
  for _, v in ipairs(conf.username_claims) do
    if claims[v] then
      secret_username = claims[v]
    end
  end

  if not secret_username then
    ngx.ctx.stop_phases = true
    return responses.send_HTTP_UNAUTHORIZED(string.format("No %s in claims", conf.username_claims[1]))
  end

  -- Retrieve the secret
  local jwt_secret = cache.get_or_set(jwt_secret_cache_key(secret_username), function()
    local rows, err = dao.jwt_secrets:find_by_keys {username = secret_username}
    if err then
      return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
    elseif #rows > 0 then
      return rows[1]
    end
  end)

  -- Now verify the JWT
  err = select(2, jwt.decode(token, jwt_secret.secret, true))
  if err == "Invalid signature" then
    ngx.ctx.stop_phases = true
    return responses.send_HTTP_FORBIDDEN("Invalid signature")
  elseif err then
    ngx.log(ngx.ERR, "[jwt]"..err)
    ngx.ctx.stop_phases = true
    return responses.send_HTTP_INTERNAL_SERVER_ERROR("Error while decoding JWT")
  end

  -- Retrieve the consumer
  local consumer = cache.get_or_set(cache.consumer_key(secret_username), function()
    local consumer, err = dao.consumers:find_by_primary_key {id = jwt_secret.consumer_id}
    if err then
      return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
    end
    return consumer
  end)

  if not consumer then
    ngx.ctx.stop_phases = true
    return responses.send_HTTP_FORBIDDEN(string.format("Could not find consumer for '%s=%s'", conf.username_claims[1], secret_username))
  end

  ngx.req.set_header(constants.HEADERS.CONSUMER_ID, consumer.id)
  ngx.req.set_header(constants.HEADERS.CONSUMER_CUSTOM_ID, consumer.custom_id)
  ngx.req.set_header(constants.HEADERS.CONSUMER_USERNAME, consumer.username)
  ngx.ctx.authenticated_entity = consumer
end

return _M
