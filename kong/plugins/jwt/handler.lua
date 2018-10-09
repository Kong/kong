local BasePlugin = require "kong.plugins.base_plugin"
local constants = require "kong.constants"
local jwt_decoder = require "kong.plugins.jwt.jwt_parser"


local fmt = string.format
local kong = kong
local type = type
local ipairs = ipairs
local tostring = tostring
local re_gmatch = ngx.re.gmatch


local JwtHandler = BasePlugin:extend()


JwtHandler.PRIORITY = 1005
JwtHandler.VERSION = "0.2.0"


--- Retrieve a JWT in a request.
-- Checks for the JWT in URI parameters, then in cookies, and finally
-- in the `Authorization` header.
-- @param request ngx request object
-- @param conf Plugin configuration
-- @return token JWT token contained in request (can be a table) or nil
-- @return err
local function retrieve_token(conf)
  local args = kong.request.get_query()
  for _, v in ipairs(conf.uri_param_names) do
    if args[v] then
      return args[v]
    end
  end

  local var = ngx.var
  for _, v in ipairs(conf.cookie_names) do
    local cookie = var["cookie_" .. v]
    if cookie and cookie ~= "" then
      return cookie
    end
  end

  local authorization_header = kong.request.get_header("authorization")
  if authorization_header then
    local iterator, iter_err = re_gmatch(authorization_header, "\\s*[Bb]earer\\s+(.+)")
    if not iterator then
      return nil, iter_err
    end

    local m, err = iterator()
    if err then
      return nil, err
    end

    if m and #m > 0 then
      return m[1]
    end
  end
end


function JwtHandler:new()
  JwtHandler.super.new(self, "jwt")
end


local function load_credential(jwt_secret_key)
  local row, err = kong.db.jwt_secrets:select_by_key(jwt_secret_key)
  if err then
    return nil, err
  end
  return row
end


local function load_consumer(consumer_id, anonymous)
  local result, err = kong.db.consumers:select { id = consumer_id }
  if not result then
    if anonymous and not err then
      err = 'anonymous consumer "' .. consumer_id .. '" not found'
    end
    return nil, err
  end
  return result
end


local function set_consumer(consumer, credential, token)
  kong.service.request.set_header(constants.HEADERS.CONSUMER_ID, consumer.id)
  kong.service.request.set_header(constants.HEADERS.CONSUMER_CUSTOM_ID, consumer.custom_id)
  kong.service.request.set_header(constants.HEADERS.CONSUMER_USERNAME, consumer.username)

  local shared_ctx = kong.ctx.shared
  local ngx_ctx = ngx.ctx -- TODO: for bc only

  shared_ctx.authenticated_consumer = consumer
  ngx_ctx.authenticated_consumer = consumer

  if credential then
    shared_ctx.authenticated_credential = credential
    shared_ctx.authenticated_jwt_token = token
    ngx_ctx.authenticated_credential = credential
    ngx_ctx.authenticated_jwt_token = token

    if credential.username then
      kong.service.request.set_header(constants.HEADERS.CREDENTIAL_USERNAME, credential.username)
    else
      kong.service.request.clear_header(constants.HEADERS.CREDENTIAL_USERNAME)
    end

    kong.service.request.clear_header(constants.HEADERS.ANONYMOUS)

  else
    kong.service.request.set_header(constants.HEADERS.ANONYMOUS, true)
  end
end


local function do_authentication(conf)
  local token, err = retrieve_token(conf)
  if err then
    kong.log.err(err)
    return kong.response.exit(500, { message = "An unexpected error occurred" })
  end

  local token_type = type(token)
  if token_type ~= "string" then
    if token_type == "nil" then
      return false, { status = 401, message = "Unauthorized" }
    elseif token_type == "table" then
      return false, { status = 401, message = "Multiple tokens provided" }
    else
      return false, { status = 401, message = "Unrecognizable token" }
    end
  end

  -- Decode token to find out who the consumer is
  local jwt, err = jwt_decoder:new(token)
  if err then
    return false, { status = 401, message = "Bad token; " .. tostring(err) }
  end

  local claims = jwt.claims
  local header = jwt.header

  local jwt_secret_key = claims[conf.key_claim_name] or header[conf.key_claim_name]
  if not jwt_secret_key then
    return false, { status = 401, message = "No mandatory '" .. conf.key_claim_name .. "' in claims" }
  end

  -- Retrieve the secret
  local jwt_secret_cache_key = kong.db.jwt_secrets:cache_key(jwt_secret_key)
  local jwt_secret, err      = kong.cache:get(jwt_secret_cache_key, nil,
                                              load_credential, jwt_secret_key)
  if err then
    kong.log.err(err)
    return kong.response.exit(500, { message = "An unexpected error occurred" })
  end

  if not jwt_secret then
    return false, { status = 403, message = "No credentials found for given '" .. conf.key_claim_name .. "'" }
  end

  local algorithm = jwt_secret.algorithm or "HS256"

  -- Verify "alg"
  if jwt.header.alg ~= algorithm then
    return false, {status = 403, message = "Invalid algorithm"}
  end

  local jwt_secret_value = algorithm ~= nil and algorithm:sub(1, 2) == "HS" and
                           jwt_secret.secret or jwt_secret.rsa_public_key

  if conf.secret_is_base64 then
    jwt_secret_value = jwt:base64_decode(jwt_secret_value)
  end

  if not jwt_secret_value then
    return false, { status = 403, message = "Invalid key/secret" }
  end

  -- Now verify the JWT signature
  if not jwt:verify_signature(jwt_secret_value) then
    return false, { status = 403, message = "Invalid signature" }
  end

  -- Verify the JWT registered claims
  local ok_claims, errors = jwt:verify_registered_claims(conf.claims_to_verify)
  if not ok_claims then
    return false, { status = 401, errors = errors }
  end

  -- Verify the JWT registered claims
  if conf.maximum_expiration ~= nil and conf.maximum_expiration > 0 then
    local ok, errors = jwt:check_maximum_expiration(conf.maximum_expiration)
    if not ok then
      return false, { status = 403, errors = errors }
    end
  end

  -- Retrieve the consumer
  local consumer_cache_key = kong.db.consumers:cache_key(jwt_secret.consumer.id)
  local consumer, err      = kong.cache:get(consumer_cache_key, nil,
                                            load_consumer,
                                            jwt_secret.consumer.id, true)
  if err then
    kong.log.err(err)
    return kong.response.exit(500, { message = "An unexpected error occurred" })
  end

  -- However this should not happen
  if not consumer then
    return false, {
      status = 403,
      message = fmt("Could not find consumer for '%s=%s'", conf.key_claim_name, jwt_secret_key)
    }
  end

  set_consumer(consumer, jwt_secret, token)

  return true
end


function JwtHandler:access(conf)
  JwtHandler.super.access(self)

  -- check if preflight request and whether it should be authenticated
  if not conf.run_on_preflight and kong.request.get_method() == "OPTIONS" then
    return
  end

  if conf.anonymous then
    local shared_ctx = kong.ctx.shared
    if shared_ctx.authenticated_credential then
      -- we're already authenticated, and we're configured for using anonymous,
      -- hence we're in a logical OR between auth methods and we're already done.
      return
    end

    local ngx_ctx = ngx.ctx -- TODO: for bc only
    if ngx_ctx.authenticated_credential then
      -- we're already authenticated, and we're configured for using anonymous,
      -- hence we're in a logical OR between auth methods and we're already done.
      return
    end
  end

  local ok, err = do_authentication(conf)
  if not ok then
    if conf.anonymous then
      -- get anonymous user
      local consumer_cache_key = kong.db.consumers:cache_key(conf.anonymous)
      local consumer, err      = kong.cache:get(consumer_cache_key, nil,
                                                load_consumer,
                                                conf.anonymous, true)
      if err then
        kong.log.err(err)
        return kong.response.exit(500, { message = "An unexpected error occurred" })
      end

      set_consumer(consumer, nil, nil)

    else
      return kong.response.exit(err.status, err.errors or { message = err.message })
    end
  end
end


return JwtHandler
