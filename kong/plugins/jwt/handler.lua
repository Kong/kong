local constants = require "kong.constants"
local jwt_decoder = require "kong.plugins.jwt.jwt_parser"


local fmt = string.format
local kong = kong
local type = type
local ipairs = ipairs
local tostring = tostring
local re_gmatch = ngx.re.gmatch


local JwtHandler = {}


JwtHandler.PRIORITY = 1005
JwtHandler.VERSION = "2.1.0"


--- Retrieve a JWT in a request.
-- Checks for the JWT in URI parameters, then in cookies, and finally
-- in the configured header_names (defaults to `[Authorization]`).
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

  local request_headers = kong.request.get_headers()
  for _, v in ipairs(conf.header_names) do
    local token_header = request_headers[v]
    if token_header then
      if type(token_header) == "table" then
        token_header = token_header[1]
      end
      local iterator, iter_err = re_gmatch(token_header, "\\s*[Bb]earer\\s+(.+)")
      if not iterator then
        kong.log.err(iter_err)
        break
      end

      local m, err = iterator()
      if err then
        kong.log.err(err)
        break
      end

      if m and #m > 0 then
        return m[1]
      end
    end
  end
end


local function load_credential(jwt_secret_key)
  local row, err = kong.db.jwt_secrets:select_by_key(jwt_secret_key)
  if err then
    return nil, err
  end
  return row
end


local function set_consumer(consumer, credential, token)
  local set_header = kong.service.request.set_header
  local clear_header = kong.service.request.clear_header

  if consumer and consumer.id then
    set_header(constants.HEADERS.CONSUMER_ID, consumer.id)
  else
    clear_header(constants.HEADERS.CONSUMER_ID)
  end

  if consumer and consumer.custom_id then
    set_header(constants.HEADERS.CONSUMER_CUSTOM_ID, consumer.custom_id)
  else
    clear_header(constants.HEADERS.CONSUMER_CUSTOM_ID)
  end

  if consumer and consumer.username then
    set_header(constants.HEADERS.CONSUMER_USERNAME, consumer.username)
  else
    clear_header(constants.HEADERS.CONSUMER_USERNAME)
  end

  kong.client.authenticate(consumer, credential)

  if credential then
    kong.ctx.shared.authenticated_jwt_token = token -- TODO: wrap in a PDK function?
    ngx.ctx.authenticated_jwt_token = token  -- backward compatibility only

    if credential.key then
      set_header(constants.HEADERS.CREDENTIAL_IDENTIFIER, credential.key)
    else
      clear_header(constants.HEADERS.CREDENTIAL_IDENTIFIER)
    end

    clear_header(constants.HEADERS.ANONYMOUS)

  else
    clear_header(constants.HEADERS.CREDENTIAL_IDENTIFIER)
    set_header(constants.HEADERS.ANONYMOUS, true)
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
  elseif jwt_secret_key == "" then
    return false, { status = 401, message = "Invalid '" .. conf.key_claim_name .. "' in claims" }
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
    return false, { status = 401, message = "No credentials found for given '" .. conf.key_claim_name .. "'" }
  end

  local algorithm = jwt_secret.algorithm or "HS256"

  -- Verify "alg"
  if jwt.header.alg ~= algorithm then
    return false, {status = 401, message = "Invalid algorithm"}
  end

  local jwt_secret_value = algorithm ~= nil and algorithm:sub(1, 2) == "HS" and
                           jwt_secret.secret or jwt_secret.rsa_public_key

  if conf.secret_is_base64 then
    jwt_secret_value = jwt:base64_decode(jwt_secret_value)
  end

  if not jwt_secret_value then
    return false, { status = 401, message = "Invalid key/secret" }
  end

  -- Now verify the JWT signature
  if not jwt:verify_signature(jwt_secret_value) then
    return false, { status = 401, message = "Invalid signature" }
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
      return false, { status = 401, errors = errors }
    end
  end

  -- Retrieve the consumer
  local consumer_cache_key = kong.db.consumers:cache_key(jwt_secret.consumer.id)
  local consumer, err      = kong.cache:get(consumer_cache_key, nil,
                                            kong.client.load_consumer,
                                            jwt_secret.consumer.id, true)
  if err then
    return kong.response.exit(500, { message = "An unexpected error occurred" })
  end

  -- However this should not happen
  if not consumer then
    return false, {
      status = 401,
      message = fmt("Could not find consumer for '%s=%s'", conf.key_claim_name, jwt_secret_key)
    }
  end

  set_consumer(consumer, jwt_secret, token)

  return true
end


function JwtHandler:access(conf)
  -- check if preflight request and whether it should be authenticated
  if not conf.run_on_preflight and kong.request.get_method() == "OPTIONS" then
    return
  end

  if conf.anonymous and kong.client.get_credential() then
    -- we're already authenticated, and we're configured for using anonymous,
    -- hence we're in a logical OR between auth methods and we're already done.
    return
  end

  local ok, err = do_authentication(conf)
  if not ok then
    if conf.anonymous then
      -- get anonymous user
      local consumer_cache_key = kong.db.consumers:cache_key(conf.anonymous)
      local consumer, err      = kong.cache:get(consumer_cache_key, nil,
                                                kong.client.load_consumer,
                                                conf.anonymous, true)
      if err then
        kong.log.err("failed to load anonymous consumer:", err)
        return kong.response.exit(500, { message = "An unexpected error occurred" })
      end

      set_consumer(consumer, nil, nil)

    else
      return kong.response.exit(err.status, err.errors or { message = err.message })
    end
  end
end


return JwtHandler
