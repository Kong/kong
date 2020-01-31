local url = require "socket.url"
local utils = require "kong.tools.utils"
local constants = require "kong.constants"
local timestamp = require "kong.tools.timestamp"


local kong = kong
local type = type
local next = next
local table = table
local split = utils.split
local strip = utils.strip
local string_find = string.find
local check_https = utils.check_https
local encode_args = utils.encode_args
local random_string = utils.random_string
local table_contains = utils.table_contains


local ngx_decode_args = ngx.decode_args
local ngx_re_gmatch = ngx.re.gmatch
local ngx_decode_base64 = ngx.decode_base64


local _M = {}


local EMPTY = {}
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


local function internal_server_error(err)
  kong.log.err(err)
  return kong.response.exit(500, { message = "An unexpected error occurred" })
end


local function generate_token(conf, service, credential, authenticated_userid,
                              scope, state, expiration, disable_refresh)

  local token_expiration = expiration or conf.token_expiration

  local refresh_token
  if not disable_refresh and token_expiration > 0 then
    refresh_token = random_string()
  end

  local refresh_token_ttl
  if conf.refresh_token_ttl and conf.refresh_token_ttl > 0 then
    refresh_token_ttl = conf.refresh_token_ttl
  end

  local service_id
  if not conf.global_credentials then
    service_id = service.id
  end

  local token, err = kong.db.oauth2_tokens:insert({
    service = service_id and { id = service_id } or nil,
    credential = { id = credential.id },
    authenticated_userid = authenticated_userid,
    expires_in = token_expiration,
    refresh_token = refresh_token,
    scope = scope
  }, {
    -- Access tokens (and their associated refresh token) are being
    -- permanently deleted after 'refresh_token_ttl' seconds
    ttl = token_expiration > 0 and refresh_token_ttl or nil
  })

  if err then
    return internal_server_error(err)
  end

  return {
    access_token = token.access_token,
    token_type = "bearer",
    expires_in = token_expiration > 0 and token.expires_in or nil,
    refresh_token = refresh_token,
    state = state -- If state is nil, this value won't be added
  }
end

local function load_oauth2_credential_by_client_id(client_id)
  local credential, err = kong.db.oauth2_credentials:select_by_client_id(client_id)
  if err then
    return nil, err
  end

  return credential
end

local function get_redirect_uris(client_id)
  local client, err
  if client_id and client_id ~= "" then
    local credential_cache_key = kong.db.oauth2_credentials:cache_key(client_id)
    client, err = kong.cache:get(credential_cache_key, nil,
                                 load_oauth2_credential_by_client_id,
                                 client_id)
    if err then
      return internal_server_error(err)
    end
  end

  return client and client.redirect_uris or nil, client
end

local function retrieve_parameters()
  -- OAuth2 parameters could be in both the querystring or body
  local uri_args = kong.request.get_query()
  local method   = kong.request.get_method()

  if method == "POST" or method == "PUT" or method == "PATCH" then
    local body_args = kong.request.get_body()

    return kong.table.merge(uri_args, body_args)
  end

  return uri_args
end

local function retrieve_scope(parameters, conf)
  local scope = parameters[SCOPE]
  local scopes = {}

  if conf.scopes and scope ~= nil then
    if type(scope) ~= "string" then
      return nil, {[ERROR] = "invalid_scope", error_description = "scope must be a string"}
    end

    for v in scope:gmatch("%S+") do
      if not table_contains(conf.scopes, v) then
        return nil, {[ERROR] = "invalid_scope", error_description = "\"" .. v .. "\" is an invalid " .. SCOPE}
      else
        table.insert(scopes, v)
      end
    end

  elseif not scope and conf.mandatory_scope then
    return nil, {[ERROR] = "invalid_scope", error_description = "You must specify a " .. SCOPE}
  end

  if #scopes > 0 then
    return table.concat(scopes, " ")
  end -- else return nil
end

local function authorize(conf)
  local response_params = {}
  local parameters = retrieve_parameters()
  local state = parameters[STATE]
  local allowed_redirect_uris, client, redirect_uri, parsed_redirect_uri
  local is_implicit_grant

  local is_https, err = check_https(kong.ip.is_trusted(kong.client.get_ip()),
                                    conf.accept_http_if_already_terminated)
  if not is_https then
    response_params = {
      [ERROR] = "access_denied",
      error_description = err or "You must use HTTPS"
    }

  else
    if conf.provision_key ~= parameters.provision_key then
      response_params = {
        [ERROR] = "invalid_provision_key",
        error_description = "Invalid provision_key"
      }

    elseif not parameters.authenticated_userid or strip(parameters.authenticated_userid) == "" then
      response_params = {
        [ERROR] = "invalid_authenticated_userid",
        error_description = "Missing authenticated_userid parameter"
      }

    else
      local response_type = parameters[RESPONSE_TYPE]

      -- Check response_type
      if not ((response_type == CODE and conf.enable_authorization_code) or
              (conf.enable_implicit_grant and response_type == TOKEN)) then
        -- Auth Code Grant (http://tools.ietf.org/html/rfc6749#section-4.1.1)
        response_params = {
          [ERROR] = "unsupported_response_type",
          error_description = "Invalid " .. RESPONSE_TYPE
        }
      end

      -- Check scopes
      local scopes, err = retrieve_scope(parameters, conf)
      if err then
        response_params = err -- If it's not ok, then this is the error message
      end

      -- Check client_id and redirect_uri
      allowed_redirect_uris, client = get_redirect_uris(parameters[CLIENT_ID])

      if not allowed_redirect_uris then
        response_params = {
          [ERROR] = "invalid_client",
          error_description = "Invalid client authentication"
        }

      else
        redirect_uri = parameters[REDIRECT_URI] and
                       parameters[REDIRECT_URI] or
                       allowed_redirect_uris[1]

        if not table_contains(allowed_redirect_uris, redirect_uri) then
          response_params = {
            [ERROR] = "invalid_request",
            error_description = "Invalid " .. REDIRECT_URI ..
                                " that does not match with any redirect_uri" ..
                                " created with the application"
          }

          -- redirect_uri used in this case is the first one registered with
          -- the application
          redirect_uri = allowed_redirect_uris[1]
        end
      end

      parsed_redirect_uri = url.parse(redirect_uri)

      -- If there are no errors, keep processing the request
      if not response_params[ERROR] then
        if response_type == CODE then
          local service_id
          if not conf.global_credentials then
            service_id = (kong.router.get_service() or EMPTY).id
          end

          local auth_code, err = kong.db.oauth2_authorization_codes:insert({
            service = service_id and { id = service_id } or nil,
            credential = { id = client.id },
            authenticated_userid = parameters[AUTHENTICATED_USERID],
            scope = scopes
          }, {
            ttl = 300
          })

          if err then
            return internal_server_error(err)
          end

          response_params = {
            code = auth_code.code,
          }

        else
          -- Implicit grant, override expiration to zero
          response_params = generate_token(conf, kong.router.get_service(),
                                           client,
                                           parameters[AUTHENTICATED_USERID],
                                           scopes, state, nil, true)
          is_implicit_grant = true
        end
      end
    end
  end

  -- Adding the state if it exists. If the state == nil then it won't be added
  response_params.state = state

  -- Appending kong generated params to redirect_uri query string
  if parsed_redirect_uri then
    local encoded_params = encode_args(kong.table.merge(ngx_decode_args(
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
  local status = response_params[ERROR] and 400 or 200
  local body
  if redirect_uri then
    body = { redirect_uri = url.build(parsed_redirect_uri) }

  else
    body = response_params
  end

  return kong.response.exit(status, body, {
    ["cache-control"] = "no-store",
    ["pragma"] = "no-cache"
  })
end

local function retrieve_client_credentials(parameters, conf)
  local client_id, client_secret, from_authorization_header
  local authorization_header = kong.request.get_header(conf.auth_header_name)

  if parameters[CLIENT_ID] and parameters[CLIENT_SECRET] then
    client_id = parameters[CLIENT_ID]
    client_secret = parameters[CLIENT_SECRET]

  elseif authorization_header then
    from_authorization_header = true

    local iterator, iter_err = ngx_re_gmatch(authorization_header,
                                             "\\s*[Bb]asic\\s*(.+)")
    if not iterator then
      kong.log.err(iter_err)
      return
    end

    local m, err = iterator()
    if err then
      kong.log.err(err)
      return
    end

    if m and next(m) then
      local decoded_basic = ngx_decode_base64(m[1])
      if decoded_basic then
        local basic_parts = split(decoded_basic, ":")
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

  local is_https, err = check_https(kong.ip.is_trusted(kong.client.get_ip()),
                                    conf.accept_http_if_already_terminated)
  if not is_https then
    response_params = {
      [ERROR] = "access_denied",
      error_description = err or "You must use HTTPS"
    }

  else
    local grant_type = parameters[GRANT_TYPE]
    if not (grant_type == GRANT_AUTHORIZATION_CODE or
            grant_type == GRANT_REFRESH_TOKEN or
            (conf.enable_client_credentials and
             grant_type == GRANT_CLIENT_CREDENTIALS) or
            (conf.enable_password_grant and grant_type == GRANT_PASSWORD)) then
      response_params = {
        [ERROR] = "unsupported_grant_type",
        error_description = "Invalid " .. GRANT_TYPE
      }
    end

    local client_id, client_secret, from_authorization_header =
      retrieve_client_credentials(parameters, conf)

    -- Check client_id and redirect_uri
    local allowed_redirect_uris, client = get_redirect_uris(client_id)
    if not (grant_type == GRANT_CLIENT_CREDENTIALS) then
      if allowed_redirect_uris then
        local redirect_uri = parameters[REDIRECT_URI] and
          parameters[REDIRECT_URI] or
          allowed_redirect_uris[1]

        if not table_contains(allowed_redirect_uris, redirect_uri) then
          response_params = {
            [ERROR] = "invalid_request",
            error_description = "Invalid " .. REDIRECT_URI .. " that does " ..
              "not match with any redirect_uri created "  ..
              "with the application"
          }
        end

      else
        response_params = {
          [ERROR] = "invalid_client",
          error_description = "Invalid client authentication"
        }

        if from_authorization_header then
          invalid_client_properties = {
            status = 401,
            www_authenticate = "Basic realm=\"OAuth2.0\""
          }
        end
      end
    end

    if client and client.client_secret ~= client_secret then
      response_params = {
        [ERROR] = "invalid_client",
        error_description = "Invalid client authentication"
      }

      if from_authorization_header then
        invalid_client_properties = {
          status = 401,
          www_authenticate = "Basic realm=\"OAuth2.0\""
        }
      end
    end

    if not response_params[ERROR] then
      if grant_type == GRANT_AUTHORIZATION_CODE then
        local code = parameters[CODE]

        local service_id
        if not conf.global_credentials then
          service_id = (kong.router.get_service() or EMPTY).id
        end

        local auth_code =
          code and kong.db.oauth2_authorization_codes:select_by_code(code)

        if not auth_code or (service_id and service_id ~= auth_code.service.id)
        then
          response_params = {
            [ERROR] = "invalid_request",
            error_description = "Invalid " .. CODE
          }

        elseif auth_code.credential.id ~= client.id then
          response_params = {
            [ERROR] = "invalid_request",
            error_description = "Invalid " .. CODE
          }

        else
          response_params = generate_token(conf, kong.router.get_service(),
                                           client,
                                           auth_code.authenticated_userid,
                                           auth_code.scope, state)

          -- Delete authorization code so it cannot be reused
          kong.db.oauth2_authorization_codes:delete({ id = auth_code.id })
        end

      elseif grant_type == GRANT_CLIENT_CREDENTIALS then
        -- Only check the provision_key if the authenticated_userid is being set
        if parameters.authenticated_userid and
           conf.provision_key ~= parameters.provision_key then
          response_params = {
            [ERROR] = "invalid_provision_key",
            error_description = "Invalid provision_key"
          }

        elseif not client then
          response_params = {
            [ERROR] = "invalid_client",
            error_description = "Invalid client authentication"
          }

        else
          -- Check scopes
          local scope, err = retrieve_scope(parameters, conf)
          if err then
            -- If it's not ok, then this is the error message
            response_params = err

          else
            response_params = generate_token(conf, kong.router.get_service(),
                                             client,
                                             parameters.authenticated_userid,
                                             scope, state, nil, true)
          end
        end

      elseif grant_type == GRANT_PASSWORD then
        -- Check that it comes from the right client
        if conf.provision_key ~= parameters.provision_key then
          response_params = {
            [ERROR] = "invalid_provision_key",
            error_description = "Invalid provision_key"
          }

        elseif not parameters.authenticated_userid or
               strip(parameters.authenticated_userid) == "" then
          response_params = {
            [ERROR] = "invalid_authenticated_userid",
            error_description = "Missing authenticated_userid parameter"
          }

        else
          -- Check scopes
          local scope, err = retrieve_scope(parameters, conf)
          if err then
            -- If it's not ok, then this is the error message
            response_params = err

          else
            response_params = generate_token(conf, kong.router.get_service(),
                                             client,
                                             parameters.authenticated_userid,
                                             scope, state)
          end
        end

      elseif grant_type == GRANT_REFRESH_TOKEN then
        local refresh_token = parameters[REFRESH_TOKEN]

        local service_id
        if not conf.global_credentials then
          service_id = (kong.router.get_service() or EMPTY).id
        end

        local token = refresh_token and
                      kong.db.oauth2_tokens:select_by_refresh_token(refresh_token)

        if not token or (service_id and service_id ~= token.service.id) then
          response_params = {
            [ERROR] = "invalid_request",
            error_description = "Invalid " .. REFRESH_TOKEN
          }

        else
          -- Check that the token belongs to the client application
          if token.credential.id ~= client.id then
            response_params = {
              [ERROR] = "invalid_client",
              error_description = "Invalid client authentication"
            }

          else
            response_params = generate_token(conf, kong.router.get_service(),
                                             client,
                                             token.authenticated_userid,
                                             token.scope, state)
            -- Delete old token
            kong.db.oauth2_tokens:delete({ id = token.id })
          end
        end
      end
    end
  end

  -- Adding the state if it exists. If the state == nil then it won't be added
  response_params.state = state

  -- Sending response in JSON format
  return kong.response.exit(response_params[ERROR] and
                             (invalid_client_properties and
                              invalid_client_properties.status or 400) or 200,
                              response_params, {
                                ["cache-control"] = "no-store",
                                ["pragma"] = "no-cache",
                                ["www-authenticate"] = invalid_client_properties and
                                                       invalid_client_properties.www_authenticate
                              }
                            )
end

local function load_token(conf, service, access_token)
  local credentials, err =
    kong.db.oauth2_tokens:select_by_access_token(access_token)

  if err then
    return nil, err
  end

  if not credentials then
    return
  end

  if not conf.global_credentials then
    if not credentials.service then
      return kong.response.exit(401, {
        [ERROR] = "invalid_token",
        error_description = "The access token is global, but the current " ..
                            "plugin is configured without 'global_credentials'",
      })
    end

    if credentials.service.id ~= service.id then
      credentials = nil
    end
  end

  return credentials
end

local function retrieve_token(conf, access_token)
  local token, err

  if access_token then
    local token_cache_key = kong.db.oauth2_tokens:cache_key(access_token)
    token, err = kong.cache:get(token_cache_key, nil,
                                load_token, conf,
                                kong.router.get_service(),
                                access_token)
    if err then
      return internal_server_error(err)
    end
  end

  return token
end

local function parse_access_token(conf)
  local found_in = {}

  local access_token = kong.request.get_header(conf.auth_header_name)
  if access_token then
    local parts = {}
    for v in access_token:gmatch("%S+") do -- Split by space
      table.insert(parts, v)
    end

    if #parts == 2 and (parts[1]:lower() == "token" or
                        parts[1]:lower() == "bearer") then
      access_token = parts[2]
      found_in.authorization_header = true
    end

  else
    access_token = retrieve_parameters()[ACCESS_TOKEN]
    if type(access_token) ~= "string" then
      return
    end
  end

  if conf.hide_credentials then
    if found_in.authorization_header then
      kong.service.request.clear_header(conf.auth_header_name)

    else
      -- Remove from querystring
      local parameters = kong.request.get_query()
      parameters[ACCESS_TOKEN] = nil
      kong.service.request.set_query(parameters)

      local content_type = kong.request.get_header("content-type")
      local is_form_post = content_type and
        string_find(content_type, "application/x-www-form-urlencoded", 1, true)

      if kong.request.get_method() ~= "GET" and is_form_post then
        -- Remove from body
        parameters = kong.request.get_body() or {}
        parameters[ACCESS_TOKEN] = nil
        kong.service.request.set_body(parameters)
      end
    end
  end

  return access_token
end

local function load_oauth2_credential_into_memory(credential_id)
  local result, err = kong.db.oauth2_credentials:select { id = credential_id }
  if err then
    return nil, err
  end

  return result
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
    if token.scope then
      set_header("x-authenticated-scope", token.scope)
    else
      clear_header("x-authenticated-scope")
    end

    if token.authenticated_userid then
      set_header("x-authenticated-userid", token.authenticated_userid)
    else
      clear_header("x-authenticated-userid")
    end

    clear_header(constants.HEADERS.ANONYMOUS) -- in case of auth plugins concatenation

  else
    set_header(constants.HEADERS.ANONYMOUS, true)
    clear_header("x-authenticated-scope")
    clear_header("x-authenticated-userid")
  end

end

local function do_authentication(conf)
  local access_token = parse_access_token(conf);
  if not access_token or access_token == "" then
    return nil, {
      status = 401,
      message = {
        [ERROR] = "invalid_request",
        error_description = "The access token is missing"
      },
      headers = {
        ["WWW-Authenticate"] = 'Bearer realm="service"'
      }
    }
  end

  local token = retrieve_token(conf, access_token)
  if not token then
    return nil, {
      status = 401,
      message = {
        [ERROR] = "invalid_token",
        error_description = "The access token is invalid or has expired"
      },
      headers = {
        ["WWW-Authenticate"] = 'Bearer realm="service" error=' ..
                               '"invalid_token" error_description=' ..
                               '"The access token is invalid or has expired"'
      }
    }
  end

  if (token.service and token.service.id and
      kong.router.get_service().id ~= token.service.id) or
      ((not token.service or not token.service.id) and
        not conf.global_credentials) then
    return nil, {
      status = 401,
      message = {
        [ERROR] = "invalid_token",
        error_description = "The access token is invalid or has expired"
      },
      headers = {
        ["WWW-Authenticate"] = 'Bearer realm="service" error=' ..
                               '"invalid_token" error_description=' ..
                               '"The access token is invalid or has expired"'
      }
    }
  end

  -- Check expiration date
  if token.expires_in > 0 then -- zero means the token never expires
    local now = timestamp.get_utc() / 1000
    if now - token.created_at > token.expires_in then
      return nil, {
        status = 401,
        message = {
          [ERROR] = "invalid_token",
          error_description = "The access token is invalid or has expired"
        },
        headers = {
          ["WWW-Authenticate"] = 'Bearer realm="service" error=' ..
                                 '"invalid_token" error_description=' ..
                                 '"The access token is invalid or has expired"'
        }
      }
    end
  end

  -- Retrieve the credential from the token
  local credential_cache_key =
    kong.db.oauth2_credentials:cache_key(token.credential.id)

  local credential, err = kong.cache:get(credential_cache_key, nil,
                                         load_oauth2_credential_into_memory,
                                         token.credential.id)
  if err then
    return internal_server_error(err)
  end

  -- Retrieve the consumer from the credential
  local consumer_cache_key, consumer
  consumer_cache_key = kong.db.consumers:cache_key(credential.consumer.id)
  consumer, err      = kong.cache:get(consumer_cache_key, nil,
                                      kong.client.load_consumer,
                                      credential.consumer.id)
  if err then
    return internal_server_error(err)
  end

  set_consumer(consumer, credential, token)

  return true
end


function _M.execute(conf)
  if conf.anonymous and kong.client.get_credential() then
    -- we're already authenticated, and we're configured for using anonymous,
    -- hence we're in a logical OR between auth methods and we're already done.
    return
  end

  if kong.request.get_method() == "POST" then
    local path = kong.request.get_path()

    local from = string_find(path, "/oauth2/token", nil, true)
    if from then
      return issue_token(conf)
    end

    from = string_find(path, "/oauth2/authorize", nil, true)
    if from then
      return authorize(conf)
    end
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
      return kong.response.exit(err.status, err.message, err.headers)
    end
  end
end


return _M
