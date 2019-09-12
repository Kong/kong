local constants = require "kong.constants"
local singletons = require "kong.singletons"
local ldap = require "kong.plugins.ldap-auth.ldap"


local kong = kong
local decode_base64 = ngx.decode_base64
local tostring =  tostring
local match = string.match
local lower = string.lower
local upper = string.upper
local find = string.find
local sub = string.sub
local fmt = string.format
local tcp = ngx.socket.tcp
local md5 = ngx.md5


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
  local err, suppressed_err, ok, _

  local sock = tcp()

  sock:settimeout(conf.timeout)

  local opts

  -- keep TLS connections in a separate pool to avoid reusing non-secure
  -- connections and vice-versa, because STARTTLS use the same port
  if conf.start_tls then
    opts = {
      pool = conf.ldap_host .. ":" .. conf.ldap_port .. ":starttls"
    }
  end

  ok, err = sock:connect(conf.ldap_host, conf.ldap_port, opts)
  if not ok then
    kong.log.err("failed to connect to ", conf.ldap_host, ":",
                   tostring(conf.ldap_port), ": ", err)
    return nil, err
  end

  if conf.start_tls then
    -- convert connection to a STARTTLS connection only if it is a new connection
    local count, err = sock:getreusedtimes()
    if not count then
      -- connection was closed, just return instead
      return nil, err
    end

    if count == 0 then
      local ok, err = ldap.start_tls(sock)
      if not ok then
        return nil, err
      end
    end
  end

  if conf.start_tls or conf.ldaps then
    _, err = sock:sslhandshake(true, conf.ldap_host, conf.verify_ldap_host)
    if err ~= nil then
      return false, fmt("failed to do SSL handshake with %s:%s: %s",
                        conf.ldap_host, tostring(conf.ldap_port), err)
    end
  end

  local who = conf.attribute .. "=" .. given_username .. "," .. conf.base_dn
  is_authenticated, err = ldap.bind_request(sock, who, given_password)

  ok, suppressed_err = sock:setkeepalive(conf.keepalive)
  if not ok then
    kong.log.err("failed to keepalive to ", conf.ldap_host, ":",
                   tostring(conf.ldap_port), ": ", suppressed_err)
  end

  return is_authenticated, err
end

local function load_credential(given_username, given_password, conf)
  local ok, err = ldap_authenticate(given_username, given_password, conf)
  if err ~= nil then
    kong.log.err(err)
  end

  if ok == nil then
    return nil
  end

  if ok == false then
    return false
  end

  return { username = given_username, password = given_password }
end


local function cache_key(conf, username, password)
  if not ldap_config_cache[conf] then
    ldap_config_cache[conf] = md5(fmt("%s:%u:%s:%s:%u",
                                      lower(conf.ldap_host),
                                      conf.ldap_port,
                                      conf.base_dn,
                                      conf.attribute,
                                      conf.cache_ttl))
  end

  return fmt("ldap_auth_cache:%s:%s:%s", ldap_config_cache[conf],
             username, password)
end


local function authenticate(conf, given_credentials)
  local given_username, given_password = retrieve_credentials(given_credentials, conf)
  if given_username == nil then
    return false
  end

  local credential, err = singletons.cache:get(cache_key(conf, given_username, given_password), {
    ttl = conf.cache_ttl,
    neg_ttl = conf.cache_ttl
  }, load_credential, given_username, given_password, conf)

  if err or credential == nil then
    kong.log.err(err)
    return kong.response.exit(500, { message = "An unexpected error occurred" })
  end

  return credential and credential.password == given_password, credential
end


local function set_consumer(consumer, credential)
  kong.client.authenticate(consumer, credential)

  local set_header = kong.service.request.set_header
  local clear_header = kong.service.request.clear_header

  if consumer then
    -- this can only be the Anonymous user in this case
    if consumer.id then
      set_header(constants.HEADERS.CONSUMER_ID, consumer.id)
    else
      clear_header(constants.HEADERS.CONSUMER_ID)
    end

    if consumer.custom_id then
      set_header(constants.HEADERS.CONSUMER_CUSTOM_ID, consumer.custom_id)
    else
      clear_header(constants.HEADERS.CONSUMER_CUSTOM_ID)
    end

    if consumer.username then
      set_header(constants.HEADERS.CONSUMER_USERNAME, consumer.username)
    else
      clear_header(constants.HEADERS.CONSUMER_USERNAME)
    end

    set_header(constants.HEADERS.ANONYMOUS, true)

    return
  end

  if credential and credential.username then
    set_header(constants.HEADERS.CREDENTIAL_USERNAME, credential.username)
  else
    clear_header(constants.HEADERS.CREDENTIAL_USERNAME)
  end

  -- in case of auth plugins concatenation, remove remnants of anonymous
  clear_header(constants.HEADERS.ANONYMOUS)
  clear_header(constants.HEADERS.CONSUMER_ID)
  clear_header(constants.HEADERS.CONSUMER_CUSTOM_ID)
  clear_header(constants.HEADERS.CONSUMER_USERNAME)
end


local function do_authentication(conf)
  local authorization_value = kong.request.get_header(AUTHORIZATION)
  local proxy_authorization_value = kong.request.get_header(PROXY_AUTHORIZATION)

  -- If both headers are missing, return 401
  if not (authorization_value or proxy_authorization_value) then
    local scheme = conf.header_type
    if scheme == "ldap" then
      -- ensure backwards compatibility (see GH PR #3656)
      -- TODO: provide migration to capitalize older configurations
      scheme = upper(scheme)
    end

    return false, {
      status = 401,
      message = "Unauthorized",
      headers = { ["WWW-Authenticate"] = scheme .. ' realm="kong"' }
    }
  end

  local is_authorized, credential = authenticate(conf, proxy_authorization_value)
  if not is_authorized then
    is_authorized, credential = authenticate(conf, authorization_value)
  end

  if not is_authorized then
    return false, {status = 401, message = "Invalid authentication credentials" }
  end

  if conf.hide_credentials then
    kong.service.request.clear_header(AUTHORIZATION)
    kong.service.request.clear_header(PROXY_AUTHORIZATION)
  end

  set_consumer(nil, credential)

  return true
end


function _M.execute(conf)
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
      local consumer, err      = singletons.cache:get(consumer_cache_key, nil,
                                                      kong.client.load_consumer,
                                                      conf.anonymous, true)
      if err then
        kong.log.err("failed to load anonymous consumer:", err)
        return kong.response.exit(500, { message = "An unexpected error occurred" })
      end

      set_consumer(consumer, nil)

    else
      return kong.response.exit(err.status, { message = err.message }, err.headers)
    end
  end
end


return _M
