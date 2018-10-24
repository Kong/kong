local responses = require "kong.tools.responses"
local constants = require "kong.constants"
local singletons = require "kong.singletons"
local ldap = require "kong.plugins.ldap-auth.ldap"

local match = string.match
local lower = string.lower
local upper = string.upper
local find = string.find
local sub = string.sub
local fmt = string.format
local ngx_log = ngx.log
local request = ngx.req
local ngx_error = ngx.ERR
local md5 = ngx.md5
local decode_base64 = ngx.decode_base64
local ngx_socket_tcp = ngx.socket.tcp
local ngx_set_header = ngx.req.set_header
local tostring =  tostring

local AUTHORIZATION = "authorization"
local PROXY_AUTHORIZATION = "proxy-authorization"


local ldap_config_cache = setmetatable({}, { __mode = "k" })


local _M = {}

local function retrieve_credentials(authorization_header_value, conf)
  local username, password
  if authorization_header_value then
    local s, e = find(lower(authorization_header_value), "^%s*" ..
                      lower(conf.header_type) .. "%s+")
    if s == 1 then
      local cred = sub(authorization_header_value, e + 1)
      local decoded_cred = decode_base64(cred)
      username, password = match(decoded_cred, "(.+):(.+)")
    end
  end
  return username, password
end

local function ldap_authenticate(given_username, given_password, conf)
  local is_authenticated
  local err, suppressed_err, ok

  local sock = ngx_socket_tcp()
  sock:settimeout(conf.timeout)
  ok, err = sock:connect(conf.ldap_host, conf.ldap_port)
  if not ok then
    ngx_log(ngx_error, "[ldap-auth] failed to connect to ", conf.ldap_host,
            ":", tostring(conf.ldap_port),": ", err)
    return nil, err
  end

  if conf.start_tls then
    local success, err = ldap.start_tls(sock)
    if not success then
      return false, err
    end
    local _, err = sock:sslhandshake(true, conf.ldap_host, conf.verify_ldap_host)
    if err ~= nil then
      return false, fmt("failed to do SSL handshake with %s:%s: %s",
                        conf.ldap_host, tostring(conf.ldap_port), err)
    end
  end

  local who = conf.attribute .. "=" .. given_username .. "," .. conf.base_dn
  is_authenticated, err = ldap.bind_request(sock, who, given_password)

  ok, suppressed_err = sock:setkeepalive(conf.keepalive)
  if not ok then
    ngx_log(ngx_error, "[ldap-auth] failed to keepalive to ", conf.ldap_host, ":",
            tostring(conf.ldap_port), ": ", suppressed_err)
  end
  return is_authenticated, err
end

local function load_credential(given_username, given_password, conf)
  local ok, err = ldap_authenticate(given_username, given_password, conf)
  if err ~= nil then
    ngx_log(ngx_error, err)
  end

  if ok == nil then
    return nil
  end
  if ok == false then
    return false
  end
  return {username = given_username, password = given_password}
end


local function cache_key(conf, username, password)
  if not ldap_config_cache[conf] then
    ldap_config_cache[conf] = md5(fmt("%s:%u:%s:%s:%u",
      lower(conf.ldap_host),
      conf.ldap_port,
      conf.base_dn,
      conf.attribute,
      conf.cache_ttl
    ))
  end

  return fmt("ldap_auth_cache:%s:%s:%s", ldap_config_cache[conf],
             username, password)
end


local function authenticate(conf, given_credentials)
  local given_username, given_password = retrieve_credentials(given_credentials,
                                                              conf)
  if given_username == nil then
    return false
  end

  local credential, err = singletons.cache:get(cache_key(conf, given_username, given_password), {
    ttl = conf.cache_ttl,
    neg_ttl = conf.cache_ttl
  }, load_credential, given_username, given_password, conf)
  if err or credential == nil then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end

  return credential and credential.password == given_password, credential
end

local function load_consumer(consumer_id, anonymous)
  local result, err = singletons.db.consumers:select { id = consumer_id }
  if not result then
    if anonymous and not err then
      err = 'anonymous consumer "' .. consumer_id .. '" not found'
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
    local scheme = conf.header_type
    if scheme == "ldap" then
      -- ensure backwards compatibility (see GH PR #3656)
      -- TODO: provide migration to capitalize older configurations
      scheme = upper(scheme)
    end

    ngx.header["WWW-Authenticate"] = scheme .. ' realm = "kong"'
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
      local consumer_cache_key = singletons.db.consumers:cache_key(conf.anonymous)
      local consumer, err      = singletons.cache:get(consumer_cache_key, nil,
                                                      load_consumer,
                                                      conf.anonymous, true)
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
