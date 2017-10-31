local url = require "socket.url"
local utils = require "kong.tools.utils"
local responses = require "kong.tools.responses"
local constants = require "kong.constants"
local timestamp = require "kong.tools.timestamp"
local singletons = require "kong.singletons"
local public_utils = require "kong.tools.public"

local string_find = string.find
local req_get_headers = ngx.req.get_headers
local ngx_set_header = ngx.req.set_header
local check_https = utils.check_https


local _M = {}

local CONTENT_LENGTH = "content-length"
local CONTENT_TYPE = "content-type"
local RESPONSE_TYPE = "response_type"
local STATE = "state"
local CODE = "code"
local TOKEN = "token"
local REFRESH_TOKEN = "refresh_token"
local SCOPE = "scope"
local CLIENT_ID = "client_id"
local CLIENT_SECRET = "client_secret"
local REDIRECT_URI = "redirect_uri"
local ACCESS_TOKEN = "access_token"
local GRANT_TYPE = "grant_type"
local GRANT_AUTHORIZATION_CODE = "authorization_code"
local GRANT_CLIENT_CREDENTIALS = "client_credentials"
local GRANT_REFRESH_TOKEN = "refresh_token"
local GRANT_PASSWORD = "password"
local ERROR = "error"
local AUTHENTICATED_USERID = "authenticated_userid"

local function generate_token(conf, api, credential, authenticated_userid, scope, state, expiration, disable_refresh)
  local token_expiration = expiration or conf.token_expiration

  local refresh_token
  if not disable_refresh and token_expiration > 0 then
    refresh_token = utils.random_string()
  end

  local refresh_token_ttl
  if conf.refresh_token_ttl and conf.refresh_token_ttl > 0 then
    refresh_token_ttl = conf.refresh_token_ttl
  end

  local api_id
  if not conf.global_credentials then
    api_id = api.id
  end
  local token, err = singletons.dao.oauth2_tokens:insert({
    api_id = api_id,
    credential_id = credential.id,
    authenticated_userid = authenticated_userid,
    expires_in = token_expiration,
    refresh_token = refresh_token,
    scope = scope
  }, {ttl = token_expiration > 0 and refresh_token_ttl or nil}) -- Access tokens (and their associated refresh token) are being
                                                                -- permanently deleted after 'refresh_token_ttl' seconds

  if err then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end

  return {
    access_token = token.access_token,
    token_type = "bearer",
    expires_in = token_expiration > 0 and token.expires_in or nil,
    refresh_token = refresh_token,
    state = state -- If state is nil, this value won't be added
  }
end

local function load_oauth2_credential_by_client_id_into_memory(client_id)
  local credentials, err = singletons.dao.oauth2_credentials:find_all {client_id = client_id}
  if err then
    return nil, err
  end
  return credentials[1]
end

local function get_redirect_uri(client_id)
  local client, err
  if client_id then
    local credential_cache_key = singletons.dao.oauth2_credentials:cache_key(client_id)
    client, err = singletons.cache:get(credential_cache_key, nil,
                                       load_oauth2_credential_by_client_id_into_memory,
                                       client_id)
    if err then
      return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
    end
  end
  return client and client.redirect_uri or nil, client
end

local function retrieve_parameters()
  ngx.req.read_body()

  -- OAuth2 parameters could be in both the querystring or body
  return utils.table_merge(ngx.req.get_uri_args(), public_utils.get_body_args())
end

local function retrieve_scopes(parameters, conf)
  local scope = parameters[SCOPE]
  local scopes = {}
  if conf.scopes and scope then
    for v in scope:gmatch("%S+") do
      if not utils.table_contains(conf.scopes, v) then
        return false, {[ERROR] = "invalid_scope", error_description = "\"" .. v .. "\" is an invalid " .. SCOPE}
      else
        table.insert(scopes, v)
      end
    end
  elseif not scope and conf.mandatory_scope then
    return false, {[ERROR] = "invalid_scope", error_description = "You must specify a " .. SCOPE}
  end

  return true, scopes
end

local function authorize(conf)
  local response_params = {}
  local parameters = retrieve_parameters()
  local state = parameters[STATE]
  local allowed_redirect_uris, client, redirect_uri, parsed_redirect_uri
  local is_implicit_grant

  local is_https, err = check_https(singletons.ip.trusted(ngx.var.realip_remote_addr),
                                    conf.accept_http_if_already_terminated)
  if not is_https then
    response_params = {[ERROR] = "access_denied", error_description = err or "You must use HTTPS"}
  else
    if conf.provision_key ~= parameters.provision_key then
      response_params = {[ERROR] = "invalid_provision_key", error_description = "Invalid provision_key"}
    elseif not parameters.authenticated_userid or utils.strip(parameters.authenticated_userid) == "" then
      response_params = {[ERROR] = "invalid_authenticated_userid", error_description = "Missing authenticated_userid parameter"}
    else
      local response_type = parameters[RESPONSE_TYPE]
      -- Check response_type
      if not ((response_type == CODE and conf.enable_authorization_code) or (conf.enable_implicit_grant and response_type == TOKEN)) then -- Authorization Code Grant (http://tools.ietf.org/html/rfc6749#section-4.1.1)
        response_params = {[ERROR] = "unsupported_response_type", error_description = "Invalid " .. RESPONSE_TYPE}
      end

      -- Check scopes
      local ok, scopes = retrieve_scopes(parameters, conf)
      if not ok then
        response_params = scopes -- If it's not ok, then this is the error message
      end

      -- Check client_id and redirect_uri
      allowed_redirect_uris, client = get_redirect_uri(parameters[CLIENT_ID])

      if not allowed_redirect_uris then
        response_params = {[ERROR] = "invalid_client", error_description = "Invalid client authentication" }
      else
        redirect_uri = parameters[REDIRECT_URI] and parameters[REDIRECT_URI] or allowed_redirect_uris[1]

        if not utils.table_contains(allowed_redirect_uris, redirect_uri) then
          response_params = {[ERROR] = "invalid_request", error_description = "Invalid " .. REDIRECT_URI .. " that does not match with any redirect_uri created with the application" }
          -- redirect_uri used in this case is the first one registered with the application
          redirect_uri = allowed_redirect_uris[1]
        end
      end

      parsed_redirect_uri = url.parse(redirect_uri)

      -- If there are no errors, keep processing the request
      if not response_params[ERROR] then
        if response_type == CODE then
          local api_id
          if not conf.global_credentials then
            api_id = ngx.ctx.api.id
          end
          local authorization_code, err = singletons.dao.oauth2_authorization_codes:insert({
            api_id = api_id,
            credential_id = client.id,
            authenticated_userid = parameters[AUTHENTICATED_USERID],
            scope = table.concat(scopes, " ")
          }, {ttl = 300})

          if err then
            return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
          end

          response_params = {
            code = authorization_code.code,
          }
        else
          -- Implicit grant, override expiration to zero
          response_params = generate_token(conf, ngx.ctx.api, client, parameters[AUTHENTICATED_USERID],  table.concat(scopes, " "), state, nil, true)
          is_implicit_grant = true
        end
      end
    end
  end

  -- Adding the state if it exists. If the state == nil then it won't be added
  response_params.state = state

  -- Appending kong generated params to redirect_uri query string
  if parsed_redirect_uri then
    local encoded_params = utils.encode_args(utils.table_merge(ngx.decode_args(
      (is_implicit_grant and
        (parsed_redirect_uri.fragment and parsed_redirect_uri.fragment or "") or
        (parsed_redirect_uri.query and parsed_redirect_uri.query or "")
      )), response_params))
    if is_implicit_grant then
      parsed_redirect_uri.fragment = encoded_params
    else
      parsed_redirect_uri.query = encoded_params
    end
  end

  -- Sending response in JSON format
  return responses.send(response_params[ERROR] and 400 or 200, redirect_uri and {
    redirect_uri = url.build(parsed_redirect_uri)
  } or response_params, {
    ["cache-control"] = "no-store",
    ["pragma"] = "no-cache"
  })
end

local function retrieve_client_credentials(parameters, conf)
  local client_id, client_secret, from_authorization_header
  local authorization_header = ngx.req.get_headers()[conf.auth_header_name]
  if parameters[CLIENT_ID] and parameters[CLIENT_SECRET] then
    client_id = parameters[CLIENT_ID]
    client_secret = parameters[CLIENT_SECRET]
  elseif authorization_header then
    from_authorization_header = true
    local iterator, iter_err = ngx.re.gmatch(authorization_header, "\\s*[Bb]asic\\s*(.+)")
    if not iterator then
      ngx.log(ngx.ERR, iter_err)
      return
    end

    local m, err = iterator()
    if err then
      ngx.log(ngx.ERR, err)
      return
    end

    if m and next(m) then
      local decoded_basic = ngx.decode_base64(m[1])
      if decoded_basic then
        local basic_parts = utils.split(decoded_basic, ":")
        client_id = basic_parts[1]
        client_secret = basic_parts[2]
      end
    end
  end

  return client_id, client_secret, from_authorization_header
end

local function issue_token(conf)
  local response_params = {}
  local invalid_client_properties = {}

  local parameters = retrieve_parameters()
  local state = parameters[STATE]

  local is_https, err = check_https(singletons.ip.trusted(ngx.var.realip_remote_addr),
                                    conf.accept_http_if_already_terminated)
  if not is_https then
    response_params = {[ERROR] = "access_denied", error_description = err or "You must use HTTPS"}
  else
    local grant_type = parameters[GRANT_TYPE]
    if not (grant_type == GRANT_AUTHORIZATION_CODE or
            grant_type == GRANT_REFRESH_TOKEN or
            (conf.enable_client_credentials and grant_type == GRANT_CLIENT_CREDENTIALS) or
            (conf.enable_password_grant and grant_type == GRANT_PASSWORD)) then
      response_params = {[ERROR] = "unsupported_grant_type", error_description = "Invalid " .. GRANT_TYPE}
    end

    local client_id, client_secret, from_authorization_header = retrieve_client_credentials(parameters, conf)

    -- Check client_id and redirect_uri
    local allowed_redirect_uris, client = get_redirect_uri(client_id)
    if not allowed_redirect_uris then
      response_params = {[ERROR] = "invalid_client", error_description = "Invalid client authentication"}
      if from_authorization_header then
        invalid_client_properties = { status = 401, www_authenticate = "Basic realm=\"OAuth2.0\""}
      end
    else
      local redirect_uri = parameters[REDIRECT_URI] and parameters[REDIRECT_URI] or allowed_redirect_uris[1]
      if not utils.table_contains(allowed_redirect_uris, redirect_uri) then
        response_params = {[ERROR] = "invalid_request", error_description = "Invalid " .. REDIRECT_URI .. " that does not match with any redirect_uri created with the application" }
      end
    end

    if client and client.client_secret ~= client_secret then
      response_params = {[ERROR] = "invalid_client", error_description = "Invalid client authentication"}
      if from_authorization_header then
        invalid_client_properties = { status = 401, www_authenticate = "Basic realm=\"OAuth2.0\""}
      end
    end

    if not response_params[ERROR] then
      if grant_type == GRANT_AUTHORIZATION_CODE then
        local code = parameters[CODE]
        local api_id
        if not conf.global_credentials then
          api_id = ngx.ctx.api.id
        end
        local authorization_code = code and singletons.dao.oauth2_authorization_codes:find_all({api_id = api_id, code = code})[1]
        if not authorization_code then
          response_params = {[ERROR] = "invalid_request", error_description = "Invalid " .. CODE}
        elseif authorization_code.credential_id ~= client.id then
          response_params = {[ERROR] = "invalid_request", error_description = "Invalid " .. CODE}
        else
          response_params = generate_token(conf, ngx.ctx.api, client, authorization_code.authenticated_userid, authorization_code.scope, state)
          singletons.dao.oauth2_authorization_codes:delete({id=authorization_code.id}) -- Delete authorization code so it cannot be reused
        end
      elseif grant_type == GRANT_CLIENT_CREDENTIALS then
        -- Only check the provision_key if the authenticated_userid is being set
        if parameters.authenticated_userid and conf.provision_key ~= parameters.provision_key then
          response_params = {[ERROR] = "invalid_provision_key", error_description = "Invalid provision_key"}
        else
          -- Check scopes
          local ok, scopes = retrieve_scopes(parameters, conf)
          if not ok then
            response_params = scopes -- If it's not ok, then this is the error message
          else
            response_params = generate_token(conf, ngx.ctx.api, client, parameters.authenticated_userid, table.concat(scopes, " "), state, nil, true)
          end
        end
      elseif grant_type == GRANT_PASSWORD then
        -- Check that it comes from the right client
        if conf.provision_key ~= parameters.provision_key then
          response_params = {[ERROR] = "invalid_provision_key", error_description = "Invalid provision_key"}
        elseif not parameters.authenticated_userid or utils.strip(parameters.authenticated_userid) == "" then
          response_params = {[ERROR] = "invalid_authenticated_userid", error_description = "Missing authenticated_userid parameter"}
        else
          -- Check scopes
          local ok, scopes = retrieve_scopes(parameters, conf)
          if not ok then
            response_params = scopes -- If it's not ok, then this is the error message
          else
            response_params = generate_token(conf, ngx.ctx.api, client, parameters.authenticated_userid, table.concat(scopes, " "), state)
          end
        end
      elseif grant_type == GRANT_REFRESH_TOKEN then
        local refresh_token = parameters[REFRESH_TOKEN]
        local api_id
        if not conf.global_credentials then
          api_id = ngx.ctx.api.id
        end
        local token = refresh_token and singletons.dao.oauth2_tokens:find_all({api_id = api_id, refresh_token = refresh_token})[1]
        if not token then
          response_params = {[ERROR] = "invalid_request", error_description = "Invalid " .. REFRESH_TOKEN}
        else
          -- Check that the token belongs to the client application
          if token.credential_id ~= client.id then
            response_params = {[ERROR] = "invalid_client", error_description = "Invalid client authentication"}
          else
            response_params = generate_token(conf, ngx.ctx.api, client, token.authenticated_userid, token.scope, state)
            singletons.dao.oauth2_tokens:delete({id=token.id}) -- Delete old token
          end
        end
      end
    end
  end

  -- Adding the state if it exists. If the state == nil then it won't be added
  response_params.state = state

  -- Sending response in JSON format
  return responses.send(response_params[ERROR] and (invalid_client_properties and invalid_client_properties.status or 400)
                        or 200, response_params, {
    ["cache-control"] = "no-store",
    ["pragma"] = "no-cache",
    ["www-authenticate"] = invalid_client_properties and invalid_client_properties.www_authenticate
  })
end

local function load_token_into_memory(conf, api, access_token)
  local api_id
  if not conf.global_credentials then
    api_id = api.id
  end
  local credentials, err = singletons.dao.oauth2_tokens:find_all { api_id = api_id, access_token = access_token }
  local result
  if err then
    return nil, err
  elseif #credentials > 0 then
    result = credentials[1]
  end
  return result
end

local function retrieve_token(conf, access_token)
  local token, err
  if access_token then
    local token_cache_key = singletons.dao.oauth2_tokens:cache_key(access_token)
    token, err = singletons.cache:get(token_cache_key, nil,
                                      load_token_into_memory, conf, ngx.ctx.api,
                                      access_token)
    if err then
      return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
    end
  end
  return token
end

local function parse_access_token(conf)
  local found_in = {}
  local result = retrieve_parameters()["access_token"]
  if not result then
    local authorization = ngx.req.get_headers()[conf.auth_header_name]
    if authorization then
      local parts = {}
      for v in authorization:gmatch("%S+") do -- Split by space
        table.insert(parts, v)
      end
      if #parts == 2 and (parts[1]:lower() == "token" or parts[1]:lower() == "bearer") then
        result = parts[2]
        found_in.authorization_header = true
      end
    end
  end

  if conf.hide_credentials then
    if found_in.authorization_header then
      ngx.req.clear_header(conf.auth_header_name)
    else
      -- Remove from querystring
      local parameters = ngx.req.get_uri_args()
      parameters[ACCESS_TOKEN] = nil
      ngx.req.set_uri_args(parameters)

      local content_type = req_get_headers()[CONTENT_TYPE]
      local is_form_post = content_type and
        string_find(content_type, "application/x-www-form-urlencoded", 1, true)

      if ngx.req.get_method() ~= "GET" and is_form_post then -- Remove from body
        ngx.req.read_body()
        parameters = public_utils.get_body_args()
        parameters[ACCESS_TOKEN] = nil
        local encoded_args = ngx.encode_args(parameters)
        ngx.req.set_header(CONTENT_LENGTH, #encoded_args)
        ngx.req.set_body_data(encoded_args)
      end
    end
  end

  return result
end

local function load_oauth2_credential_into_memory(credential_id)
  local result, err = singletons.dao.oauth2_credentials:find {id = credential_id}
  if err then
    return nil, err
  end
  return result
end

local function load_consumer_into_memory(consumer_id, anonymous)
  local result, err = singletons.dao.consumers:find { id = consumer_id }
  if not result then
    if anonymous and not err then
      err = 'anonymous consumer "' .. consumer_id .. '" not found'
    end
    return nil, err
  end
  return result
end
  
local function set_consumer(consumer, credential, token)
  ngx_set_header(constants.HEADERS.CONSUMER_ID, consumer.id)
  ngx_set_header(constants.HEADERS.CONSUMER_CUSTOM_ID, consumer.custom_id)
  ngx_set_header(constants.HEADERS.CONSUMER_USERNAME, consumer.username)
  ngx.ctx.authenticated_consumer = consumer
  if credential then
    ngx_set_header("x-authenticated-scope", token.scope)
    ngx_set_header("x-authenticated-userid", token.authenticated_userid)
    ngx.ctx.authenticated_credential = credential
    ngx_set_header(constants.HEADERS.ANONYMOUS, nil) -- in case of auth plugins concatenation
  else
    ngx_set_header(constants.HEADERS.ANONYMOUS, true)
  end
  
end

local function do_authentication(conf)
  local access_token = parse_access_token(conf);
  if not access_token then
    return false, {status = 401, message = {[ERROR] = "invalid_request", error_description = "The access token is missing"}, headers = {["WWW-Authenticate"] = 'Bearer realm="service"'}}
  end

  local token = retrieve_token(conf, access_token)
  if not token then
    return false, {status = 401, message = {[ERROR] = "invalid_token", error_description = "The access token is invalid or has expired"}, headers = {["WWW-Authenticate"] = 'Bearer realm="service" error="invalid_token" error_description="The access token is invalid or has expired"'}}
  end

  if (token.api_id and ngx.ctx.api.id ~= token.api_id) or (token.api_id == nil and not conf.global_credentials) then
    return false, {status = 401, message = {[ERROR] = "invalid_token", error_description = "The access token is invalid or has expired"}, headers = {["WWW-Authenticate"] = 'Bearer realm="service" error="invalid_token" error_description="The access token is invalid or has expired"'}}
  end

  -- Check expiration date
  if token.expires_in > 0 then -- zero means the token never expires
    local now = timestamp.get_utc()
    if now - token.created_at > (token.expires_in * 1000) then
      return false, {status = 401, message = {[ERROR] = "invalid_token", error_description = "The access token is invalid or has expired"}, headers = {["WWW-Authenticate"] = 'Bearer realm="service" error="invalid_token" error_description="The access token is invalid or has expired"'}}
    end
  end

  -- Retrieve the credential from the token
  local credential_cache_key = singletons.dao.oauth2_credentials:cache_key(token.credential_id)
  local credential, err = singletons.cache:get(credential_cache_key, nil,
                                               load_oauth2_credential_into_memory,
                                               token.credential_id)
  if err then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end

  -- Retrieve the consumer from the credential
  local consumer_cache_key = singletons.dao.consumers:cache_key(credential.consumer_id)
  local consumer, err      = singletons.cache:get(consumer_cache_key, nil,
                                                  load_consumer_into_memory,
                                                  credential.consumer_id)
  if err then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end

  set_consumer(consumer, credential, token)

  return true
end


function _M.execute(conf)

  if ngx.ctx.authenticated_credential and conf.anonymous ~= "" then
    -- we're already authenticated, and we're configured for using anonymous, 
    -- hence we're in a logical OR between auth methods and we're already done.
    return
  end

  if ngx.req.get_method() == "POST" then
    local uri = ngx.var.uri

    local from, _ = string_find(uri, "/oauth2/token", nil, true)

    if from then
      issue_token(conf)

    else
      from, _ = string_find(uri, "/oauth2/authorize", nil, true)

      if from then
        authorize(conf)
      end
    end
  end

  local ok, err = do_authentication(conf)
  if not ok then
    if conf.anonymous ~= "" then
      -- get anonymous user
      local consumer_cache_key = singletons.dao.consumers:cache_key(conf.anonymous)
      local consumer, err      = singletons.cache:get(consumer_cache_key, nil,
                                                      load_consumer_into_memory,
                                                      conf.anonymous, true)
      if err then
        return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
      end
      set_consumer(consumer, nil, nil)

    else
      return responses.send(err.status, err.message, err.headers)
    end
  end
end


return _M
