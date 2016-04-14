local responses = require "kong.tools.responses"
local constants = require "kong.constants"
local cache = require "kong.tools.database_cache"
local base64 = require "base64"
local ldap = require "kong.plugins.ldap-auth.ldap"

local match = string.match
local ngx_log = ngx.log
local request = ngx.req
local ngx_error = ngx.ERR
local ngx_debug = ngx.DEBUG
local ngx_socket_tcp = ngx.socket.tcp
local tostring =  tostring

local AUTHORIZATION = "authorization"
local PROXY_AUTHORIZATION = "proxy-authorization"

local _M = {}

local function retrieve_credentials(authorization_header_value, conf)
  local username, password
  if authorization_header_value then
    local cred = match(authorization_header_value, "%s*[ldap|LDAP]%s+(.*)")

    if cred ~= nil then
      local decoded_cred = base64.decode(cred)
      username, password = match(decoded_cred, "(.+):(.+)")
    end
  end
  return username, password
end

local function ldap_authenticate(given_username, given_password, conf)
  local is_authenticated
  local error, suppressed_err, ok
  local who = conf.attribute.."="..given_username..","..conf.base_dn

  local sock = ngx_socket_tcp()
  sock:settimeout(conf.timeout)
  ok, error = sock:connect(conf.ldap_host, conf.ldap_port)
  if not ok then
    ngx_log(ngx_error, "[ldap-auth] failed to connect to "..conf.ldap_host..":"..tostring(conf.ldap_port)..": ", error)
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(error)
  end

  if conf.start_tls then
    local success, error = ldap.start_tls(sock)
    if not success then
      return false, error
    end
    local _, error = sock:sslhandshake(true, conf.ldap_host, conf.verify_ldap_host)
    if error ~= nil then
      return false, "failed to do SSL handshake with "..conf.ldap_host..":"..tostring(conf.ldap_port)..": ".. error
    end
  end

  is_authenticated, error = ldap.bind_request(sock, who, given_password)

  ok, suppressed_err = sock:setkeepalive(conf.keepalive)
  if not ok then
    ngx_log(ngx_error, "[ldap-auth] failed to keepalive to "..conf.ldap_host..":"..tostring(conf.ldap_port)..": ", suppressed_err)
  end
  return is_authenticated, error
end

local function authenticate(conf, given_credentials)
  local given_username, given_password = retrieve_credentials(given_credentials)
  if given_username == nil then
    return false
  end

  local credential = cache.get_or_set(cache.ldap_credential_key(given_username), function()
    ngx_log(ngx_debug, "[ldap-auth] authenticating user against LDAP server: "..conf.ldap_host..":"..conf.ldap_port)

    local ok, err = ldap_authenticate(given_username, given_password, conf)
    if err ~= nil then ngx_log(ngx_error, err) end
    if not ok then
      return nil
    end
    return {username = given_username, password = given_password}
  end, conf.cache_ttl)

  return credential and credential.password == given_password, credential
end

function _M.execute(conf)
  local authorization_value = request.get_headers()[AUTHORIZATION]
  local proxy_authorization_value = request.get_headers()[PROXY_AUTHORIZATION]

  -- If both headers are missing, return 401
  if not (authorization_value or proxy_authorization_value) then
    ngx.header["WWW-Authenticate"] = 'LDAP realm="kong"'
    return responses.send_HTTP_UNAUTHORIZED()
  end

  local is_authorized, credential = authenticate(conf, proxy_authorization_value)
  if not is_authorized then
    is_authorized, credential = authenticate(conf, authorization_value)
  end

  if not is_authorized then
    return responses.send_HTTP_FORBIDDEN("Invalid authentication credentials")
  end

  if conf.hide_credentials then
    request.clear_header(AUTHORIZATION)
    request.clear_header(PROXY_AUTHORIZATION)
  end

  request.set_header(constants.HEADERS.CREDENTIAL_USERNAME, credential.username)
  ngx.ctx.authenticated_credential = credential
end

return _M
