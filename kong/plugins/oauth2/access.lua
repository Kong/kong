local stringy = require "stringy"
local utils = require "kong.tools.utils"
local cache = require "kong.tools.database_cache"
local responses = require "kong.tools.responses"
local constants = require "kong.constants"
local timestamp = require "kong.tools.timestamp"

local _M = {}

local CONTENT_LENGTH = "content-length"
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


local AUTHORIZE_URL = "^%s/oauth2/authorize(/?(\\?[^\\s]*)?)$"
local TOKEN_URL = "^%s/oauth2/token(/?(\\?[^\\s]*)?)$"

-- TODO: Expire token (using TTL ?)
local function generate_token(conf, credential, authenticated_userid, scope, state, expiration, disable_refresh)
  local token_expiration = expiration or conf.token_expiration

  local token, err = dao.oauth2_tokens:insert({
    credential_id = credential.id,
    authenticated_userid = authenticated_userid,
    expires_in = token_expiration,
    scope = scope
  })

  if err then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end

  local refresh_token = token_expiration > 0 and token.refresh_token or nil
  if disable_refresh then
    refresh_token = nil
  end

  return {
    access_token = token.access_token,
    token_type = "bearer",
    expires_in = token_expiration > 0 and token.expires_in or nil,
    refresh_token = refresh_token,
    state = state -- If state is nil, this value won't be added
  }
end

local function get_redirect_uri(client_id)
  local client
  if client_id then
    client = cache.get_or_set(cache.oauth2_credential_key(client_id), function()
      local credentials, err = dao.oauth2_credentials:find_by_keys { client_id = client_id }
      local result
      if err then
        return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
      elseif #credentials > 0 then
        result = credentials[1]
      end
      return result
    end)
  end
  return client and client.redirect_uri or nil, client
end

local HTTPS = "https"

local function is_https(conf)
  local result = ngx.var.scheme:lower() == HTTPS
  if not result and conf.accept_http_if_already_terminated then
    local forwarded_proto_header = ngx.req.get_headers()["x-forwarded-proto"]
    result = forwarded_proto_header and forwarded_proto_header:lower() == HTTPS
  end
  return result
end

local function retrieve_parameters()
  ngx.req.read_body()
  -- OAuth2 parameters could be in both the querystring or body
  return utils.table_merge(ngx.req.get_uri_args(), ngx.req.get_post_args())
end

local function retrieve_scopes(parameters, conf)
  local scope = parameters[SCOPE]
  local scopes = {}
  if conf.scopes and scope then
    for v in scope:gmatch("%S+") do
      if not utils.table_contains(conf.scopes, v) then
        return false, {[ERROR] = "invalid_scope", error_description = "\""..v.."\" is an invalid "..SCOPE}
      else
        table.insert(scopes, v)
      end
    end
  elseif not scope and conf.mandatory_scope then
    return false, {[ERROR] = "invalid_scope", error_description = "You must specify a "..SCOPE}
  end

  return true, scopes
end

local function authorize(conf)
  local response_params = {}

  local parameters = retrieve_parameters()
  local state = parameters[STATE]
  local redirect_uri, client

  if not is_https(conf) then
    response_params = {[ERROR] = "access_denied", error_description = "You must use HTTPS"}
  else
    if conf.provision_key ~= parameters.provision_key then
      response_params = {[ERROR] = "invalid_provision_key", error_description = "Invalid Kong provision_key"}
    elseif not parameters.authenticated_userid or stringy.strip(parameters.authenticated_userid) == "" then
      response_params = {[ERROR] = "invalid_authenticated_userid", error_description = "Missing authenticated_userid parameter"}
    else
      local response_type = parameters[RESPONSE_TYPE]
      -- Check response_type
      if not ((response_type == CODE and conf.enable_authorization_code) or (conf.enable_implicit_grant and response_type == TOKEN)) then -- Authorization Code Grant (http://tools.ietf.org/html/rfc6749#section-4.1.1)
        response_params = {[ERROR] = "unsupported_response_type", error_description = "Invalid "..RESPONSE_TYPE}
      end

      -- Check scopes
      local ok, scopes = retrieve_scopes(parameters, conf)
      if not ok then
        response_params = scopes -- If it's not ok, then this is the error message
      end

      -- Check client_id and redirect_uri
      redirect_uri, client = get_redirect_uri(parameters[CLIENT_ID])
      if not redirect_uri then
        response_params = {[ERROR] = "invalid_request", error_description = "Invalid "..CLIENT_ID}
      elseif parameters[REDIRECT_URI] and parameters[REDIRECT_URI] ~= redirect_uri then
        response_params = {[ERROR] = "invalid_request", error_description = "Invalid "..REDIRECT_URI.." that does not match with the one created with the application"}
      end

      -- If there are no errors, keep processing the request
      if not response_params[ERROR] then
        if response_type == CODE then
          local authorization_code, err = dao.oauth2_authorization_codes:insert({
            authenticated_userid = parameters[AUTHENTICATED_USERID],
            scope = table.concat(scopes, " ")
          })

          if err then
            return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
          end

          response_params = {
            code = authorization_code.code,
          }
        else
          -- Implicit grant, override expiration to zero
          response_params = generate_token(conf, client, parameters[AUTHENTICATED_USERID],  table.concat(scopes, " "), state, 0)
        end
      end
    end
  end

  -- Adding the state if it exists. If the state == nil then it won't be added
  response_params.state = state

  -- Sending response in JSON format
  return responses.send(response_params[ERROR] and 400 or 200, redirect_uri and {
    redirect_uri = redirect_uri.."?"..ngx.encode_args(response_params)
  } or response_params, false, {
    ["cache-control"] = "no-store",
    ["pragma"] = "no-cache"
  })
end

local function retrieve_client_credentials(parameters)
  local client_id, client_secret
  local authorization_header = ngx.req.get_headers()["authorization"]
  if parameters[CLIENT_ID] then
    client_id = parameters[CLIENT_ID]
    client_secret = parameters[CLIENT_SECRET]
  elseif authorization_header then
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

    if m and table.getn(m) > 0 then
      local decoded_basic = ngx.decode_base64(m[1])
      if decoded_basic then
        local basic_parts = stringy.split(decoded_basic, ":")
        client_id = basic_parts[1]
        client_secret = basic_parts[2]
      end
    end
  end

  return client_id, client_secret
end

local function issue_token(conf)
  local response_params = {}

  local parameters = retrieve_parameters() --TODO: Also from authorization header
  local state = parameters[STATE]

  if not is_https(conf) then
    response_params = {[ERROR] = "access_denied", error_description = "You must use HTTPS"}
  else
    local grant_type = parameters[GRANT_TYPE]
    if not (grant_type == GRANT_AUTHORIZATION_CODE or
            grant_type == GRANT_REFRESH_TOKEN or
            (conf.enable_client_credentials and grant_type == GRANT_CLIENT_CREDENTIALS) or
            (conf.enable_password_grant and grant_type == GRANT_PASSWORD)) then
      response_params = {[ERROR] = "invalid_request", error_description = "Invalid "..GRANT_TYPE}
    end

    local client_id, client_secret = retrieve_client_credentials(parameters)

    -- Check client_id and redirect_uri
    local redirect_uri, client = get_redirect_uri(client_id)
    if not redirect_uri then
      response_params = {[ERROR] = "invalid_request", error_description = "Invalid "..CLIENT_ID}
    elseif parameters[REDIRECT_URI] and parameters[REDIRECT_URI] ~= redirect_uri then
      response_params = {[ERROR] = "invalid_request", error_description = "Invalid "..REDIRECT_URI.." that does not match with the one created with the application"}
    end

    if client and client.client_secret ~= client_secret then
      response_params = {[ERROR] = "invalid_request", error_description = "Invalid "..CLIENT_SECRET}
    end

    if not response_params[ERROR] then
      if grant_type == GRANT_AUTHORIZATION_CODE then
        local code = parameters[CODE]
        local authorization_code = code and dao.oauth2_authorization_codes:find_by_keys({code = code})[1] or nil
        if not authorization_code then
          response_params = {[ERROR] = "invalid_request", error_description = "Invalid "..CODE}
        else
          response_params = generate_token(conf, client, authorization_code.authenticated_userid, authorization_code.scope, state)
        end
      elseif grant_type == GRANT_CLIENT_CREDENTIALS then
        -- Only check the provision_key if the authenticated_userid is being set
        if parameters.authenticated_userid and conf.provision_key ~= parameters.provision_key then
          response_params = {[ERROR] = "invalid_provision_key", error_description = "Invalid Kong provision_key"}
        else
          -- Check scopes
          local ok, scopes = retrieve_scopes(parameters, conf)
          if not ok then
            response_params = scopes -- If it's not ok, then this is the error message
          else
            response_params = generate_token(conf, client, parameters.authenticated_userid, table.concat(scopes, " "), state, conf.token_expiration, true)
          end
        end
      elseif grant_type == GRANT_PASSWORD then
        -- Check that it comes from the right client
        if conf.provision_key ~= parameters.provision_key then
          response_params = {[ERROR] = "invalid_provision_key", error_description = "Invalid Kong provision_key"}
        elseif not parameters.authenticated_userid or stringy.strip(parameters.authenticated_userid) == "" then
          response_params = {[ERROR] = "invalid_authenticated_userid", error_description = "Missing authenticated_userid parameter"}
        else
          -- Check scopes
          local ok, scopes = retrieve_scopes(parameters, conf)
          if not ok then
            response_params = scopes -- If it's not ok, then this is the error message
          else
            response_params = generate_token(conf, client, parameters.authenticated_userid, table.concat(scopes, " "), state)
          end
        end
      elseif grant_type == GRANT_REFRESH_TOKEN then
        local refresh_token = parameters[REFRESH_TOKEN]
        local token = refresh_token and dao.oauth2_tokens:find_by_keys({refresh_token = refresh_token})[1] or nil
        if not token then
          response_params = {[ERROR] = "invalid_request", error_description = "Invalid "..REFRESH_TOKEN}
        else
          response_params = generate_token(conf, client, token.authenticated_userid, token.scope, state)
          dao.oauth2_tokens:delete({id=token.id}) -- Delete old token
        end
      end
    end
  end

  -- Adding the state if it exists. If the state == nil then it won't be added
  response_params.state = state

  -- Sending response in JSON format
  return responses.send(response_params[ERROR] and 400 or 200, response_params, false, {
    ["cache-control"] = "no-store",
    ["pragma"] = "no-cache"
  })
end

local function retrieve_token(access_token)
  local token
  if access_token then
    token = cache.get_or_set(cache.oauth2_token_key(access_token), function()
      local credentials, err = dao.oauth2_tokens:find_by_keys { access_token = access_token }
      local result
      if err then
        return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
      elseif #credentials > 0 then
        result = credentials[1]
      end
      return result
    end)
  end
  return token
end

local function parse_access_token(conf)
  local found_in = {}
  local result = retrieve_parameters()["access_token"]
  if not result then
    local authorization = ngx.req.get_headers()["authorization"]
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
      ngx.req.clear_header("authorization")
    else
      -- Remove from querystring
      local parameters = ngx.req.get_uri_args()
      parameters[ACCESS_TOKEN] = nil
      ngx.req.set_uri_args(parameters)

      if ngx.req.get_method() ~= "GET" then -- Remove from body
        ngx.req.read_body()
        parameters = ngx.req.get_post_args()
        parameters[ACCESS_TOKEN] = nil
        local encoded_args = ngx.encode_args(parameters)
        ngx.req.set_header(CONTENT_LENGTH, string.len(encoded_args))
        ngx.req.set_body_data(encoded_args)
      end
    end
  end

  return result
end

function _M.execute(conf)
  -- Check if the API has a request_path and if it's being invoked with the path resolver
  local path_prefix = (ngx.ctx.api.request_path and stringy.startswith(ngx.var.request_uri, ngx.ctx.api.request_path)) and ngx.ctx.api.request_path or ""
  if stringy.endswith(path_prefix, "/") then
    path_prefix = path_prefix:sub(1, path_prefix:len() - 1)
  end

  if ngx.req.get_method() == "POST" then
    if ngx.re.match(ngx.var.request_uri, string.format(AUTHORIZE_URL, path_prefix)) then
      authorize(conf)
    elseif ngx.re.match(ngx.var.request_uri, string.format(TOKEN_URL, path_prefix)) then
      issue_token(conf)
    end
  end

  local accessToken = parse_access_token(conf);
  if not accessToken then
    return responses.send_HTTP_UNAUTHORIZED({}, false, {["WWW-Authenticate"] = 'Bearer realm="service"'})
  end

  local token = retrieve_token(accessToken)
  if not token then
    return responses.send_HTTP_UNAUTHORIZED({[ERROR] = "invalid_token", error_description = "The access token is invalid"}, false, {["WWW-Authenticate"] = 'Bearer realm="service" error="invalid_token" error_description="The access token is invalid"'})
  end

  -- Check expiration date
  if token.expires_in > 0 then -- zero means the token never expires
    local now = timestamp.get_utc()
    if now - token.created_at > (token.expires_in * 1000) then
      return responses.send_HTTP_UNAUTHORIZED({[ERROR] = "invalid_token", error_description = "The access token expired"}, false, {["WWW-Authenticate"] = 'Bearer realm="service" error="invalid_token" error_description="The access token expired"'})
    end
  end

  -- Retrive the credential from the token
  local credential = cache.get_or_set(cache.oauth2_credential_key(token.credential_id), function()
    local result, err = dao.oauth2_credentials:find_by_primary_key({id = token.credential_id})
    if err then
      return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
    end
    return result
  end)

  -- Retrive the consumer from the credential
  local consumer = cache.get_or_set(cache.consumer_key(credential.consumer_id), function()
    local result, err = dao.consumers:find_by_primary_key({id = credential.consumer_id})
    if err then
      return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
    end
    return result
  end)

  ngx.req.set_header(constants.HEADERS.CONSUMER_ID, consumer.id)
  ngx.req.set_header(constants.HEADERS.CONSUMER_CUSTOM_ID, consumer.custom_id)
  ngx.req.set_header(constants.HEADERS.CONSUMER_USERNAME, consumer.username)
  ngx.req.set_header("x-authenticated-scope", token.scope)
  ngx.req.set_header("x-authenticated-userid", token.authenticated_userid)
  ngx.ctx.authenticated_credential = credential
end

return _M
