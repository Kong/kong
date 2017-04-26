local responses = require "kong.tools.responses"
local constants = require "kong.constants"
local singletons = require "kong.singletons"
local cache = require "kong.tools.database_cache"
local ldap = require "kong.plugins.ldap-auth.ldap"

local match = string.match
local ngx_log = ngx.log
local request = ngx.req
local ngx_error = ngx.ERR
local ngx_debug = ngx.DEBUG
local decode_base64 = ngx.decode_base64
local ngx_socket_tcp = ngx.socket.tcp
local ngx_set_header = ngx.req.set_header
local tostring =  tostring

local AUTHORIZATION = "authorization"
local PROXY_AUTHORIZATION = "proxy-authorization"

local _M = {}

local function retrieve_credentials(authorization_header_value)
  local username, password
  if authorization_header_value then
    local cred = match(authorization_header_value, "%s*[ldap|LDAP]%s+(.*)")

    if cred ~= nil then
      local decoded_cred = decode_base64(cred)
      username, password = match(decoded_cred, "(.+):(.+)")
    end
  end
  return username, password
end

local function ldap_authenticate(given_username, given_password, conf)
  local is_authenticated
  local err, suppressed_err, ok
  local who = conf.attribute.."="..given_username..","..conf.base_dn

  local sock = ngx_socket_tcp()
  sock:settimeout(conf.timeout)
  ok, err = sock:connect(conf.ldap_host, conf.ldap_port)
  if not ok then
    ngx_log(ngx_error, "[ldap-auth] failed to connect to "..conf.ldap_host..":"..tostring(conf.ldap_port)..": ", err)
    return nil, err, responses.status_codes.HTTP_INTERNAL_SERVER_ERROR
  end

  if conf.start_tls then
    local success, err = ldap.start_tls(sock)
    if not success then
      return false, err
    end
    local _, err = sock:sslhandshake(true, conf.ldap_host, conf.verify_ldap_host)
    if err ~= nil then
      return false, "failed to do SSL handshake with "..conf.ldap_host..":"..tostring(conf.ldap_port)..": ".. err
    end
  end

  is_authenticated, err = ldap.bind_request(sock, who, given_password)

  ok, suppressed_err = sock:setkeepalive(conf.keepalive)
  if not ok then
    ngx_log(ngx_error, "[ldap-auth] failed to keepalive to "..conf.ldap_host..":"..tostring(conf.ldap_port)..": ", suppressed_err)
  end
  return is_authenticated, err
end

local function load_credential(given_username, given_password, conf)
  ngx_log(ngx_debug, "[ldap-auth] authenticating user against LDAP server: "..conf.ldap_host..":"..conf.ldap_port)

  local ok, err, status = ldap_authenticate(given_username, given_password, conf)
  if status ~= nil then return nil, err, status end
  if err ~= nil then ngx_log(ngx_error, err) end
  if not ok then
    return nil
  end
  return {username = given_username, password = given_password}
end

local function authenticate(conf, given_credentials)
  local given_username, given_password = retrieve_credentials(given_credentials)
  if given_username == nil then
    return false
  end

  local credential, err, status = cache.get_or_set(cache.ldap_credential_key(ngx.ctx.api.id, given_username), 
      conf.cache_ttl, load_credential, given_username, given_password, conf)
  if status then responses.send(status, err) end

  return credential and credential.password == given_password, credential
end

local function load_consumer(consumer_id, anonymous)
  local result, err = singletons.dao.consumers:find { id = consumer_id }
  if not result then
    if anonymous and not err then
      err = 'anonymous consumer "'..consumer_id..'" not found'
    end
    return nil, err
  end
  return result
end

local function set_consumer(consumer, credential)
  
  if consumer then
    -- this can only be the Anonymous user in this case
    ngx_set_header(constants.HEADERS.CONSUMER_ID, consumer.id)
    ngx_set_header(constants.HEADERS.CONSUMER_CUSTOM_ID, consumer.custom_id)
    ngx_set_header(constants.HEADERS.CONSUMER_USERNAME, consumer.username)
    ngx_set_header(constants.HEADERS.ANONYMOUS, true)
    ngx.ctx.authenticated_consumer = consumer
    return
  end
  
  -- here we have been authenticated by ldap
  ngx_set_header(constants.HEADERS.CREDENTIAL_USERNAME, credential.username)
  ngx.ctx.authenticated_credential = credential
  
  -- in case of auth plugins concatenation, remove remnants of anonymous
  ngx.ctx.authenticated_consumer = nil
  ngx_set_header(constants.HEADERS.ANONYMOUS, nil)
  ngx_set_header(constants.HEADERS.CONSUMER_ID, nil)
  ngx_set_header(constants.HEADERS.CONSUMER_CUSTOM_ID, nil)
  ngx_set_header(constants.HEADERS.CONSUMER_USERNAME, nil)

end

local function do_authentication(conf)
  local headers = request.get_headers()
  local authorization_value = headers[AUTHORIZATION]
  local proxy_authorization_value = headers[PROXY_AUTHORIZATION]

  -- If both headers are missing, return 401
  if not (authorization_value or proxy_authorization_value) then
    ngx.header["WWW-Authenticate"] = 'LDAP realm="kong"'
    return false, {status = 401}
  end

  local is_authorized, credential = authenticate(conf, proxy_authorization_value)
  if not is_authorized then
    is_authorized, credential = authenticate(conf, authorization_value)
  end

  if not is_authorized then
    return false, {status = 403, message = "Invalid authentication credentials"}
  end

  if conf.hide_credentials then
    request.clear_header(AUTHORIZATION)
    request.clear_header(PROXY_AUTHORIZATION)
  end

  set_consumer(nil, credential)

  return true
end


function _M.execute(conf)

  if ngx.ctx.authenticated_credential and conf.anonymous ~= "" then
    -- we're already authenticated, and we're configured for using anonymous, 
    -- hence we're in a logical OR between auth methods and we're already done.
    return
  end

  local ok, err = do_authentication(conf)
  if not ok then
    if conf.anonymous ~= "" then
      -- get anonymous user
      local consumer, err = cache.get_or_set(cache.consumer_key(conf.anonymous),
                       nil, load_consumer, conf.anonymous, true)
      if err then
        responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
      end
      set_consumer(consumer, nil)
    else
      return responses.send(err.status, err.message)
    end
  end
end


return _M
