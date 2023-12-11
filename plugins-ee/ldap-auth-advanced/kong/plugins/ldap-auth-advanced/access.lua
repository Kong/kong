-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local constants = require "kong.constants"
local ldap_cache = require "kong.plugins.ldap-auth-advanced.cache"
local ldap = require "kong.plugins.ldap-auth-advanced.ldap"
local ldap_groups = require "kong.plugins.ldap-auth-advanced.groups"

local clear_header = kong.service.request.clear_header

local kong = kong
local match = string.match
local lower = string.lower
local upper = string.upper
local find = string.find
local sub = string.sub
local fmt = string.format
local request = ngx.req
local decode_base64 = ngx.decode_base64
local ngx_socket_tcp = ngx.socket.tcp
local ngx_set_header = ngx.req.set_header
local tostring =  tostring
local ipairs = ipairs
local split = require("pl.stringx").split
local sha256_hex = require "kong.tools.sha256".sha256_hex

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
      username, password = match(decoded_cred, "(.-):(.+)")
    end
  end
  return username, password
end


local function check_group_membership(conf, groups_user)
  for _, groups_required in ipairs(conf.groups_required) do
    local groups_required_AND = split(groups_required, " ")
    local found = 0

    for _, group_required_AND in ipairs(groups_required_AND) do
      for _, group_user in ipairs(groups_user) do
        if group_required_AND == group_user then
          found = found + 1
        end
      end
    end

    if found == #groups_required_AND then
      return true
    end
  end

  return false
end
-- for unit tests only
_M.check_group_membership = check_group_membership


local function ldap_authenticate(given_username, given_password, conf)
  local is_authenticated
  local groups = nil
  local err, suppressed_err, ok

  local sock = ngx_socket_tcp()
  sock:settimeout(conf.timeout)

  local opts = {}

  -- keep TLS connections in a separate pool to avoid reusing non-secure
  -- connections and vica versa, because StartTLS use the same port
  if conf.start_tls then
    opts.pool = conf.ldap_host .. ":" .. conf.ldap_port .. ":starttls"
  end

  ok, err = sock:connect(conf.ldap_host, conf.ldap_port, opts)
  if not ok then
    kong.log.err("failed to connect to ", conf.ldap_host, ":",
                 tostring(conf.ldap_port),": ", err)
    return nil, nil, err
  end

  if conf.ldaps or conf.start_tls then
    -- convert connection to a StarTLS connection only if it is a new connection
    if conf.start_tls and sock:getreusedtimes() == 0 then
      local success, err = ldap.start_tls(sock)
      if not success then
        return false, nil, err
      end
    end

    local _, err = sock:sslhandshake(true, conf.ldap_host, conf.verify_ldap_host)
    if err ~= nil then
      return false, nil, fmt("failed to do SSL handshake with %s:%s: %s",
                             conf.ldap_host, tostring(conf.ldap_port), err)
    end
  end

  if conf.bind_dn then
    is_authenticated = false
    kong.log.debug("binding with ", conf.bind_dn, " and conf.ldap_password")
    ok, err = ldap.bind_request(sock, conf.bind_dn, conf.ldap_password)

    if err then
      kong.log.err("Error during bind request. ", err)
      return kong.response.exit(500, { message = "An unexpected error occurred" })
    end

    if ok then
      kong.log.debug("ldap bind successful, performing search request with base_dn:",
        conf.base_dn, ", scope='sub', and filter=", conf.attribute .. "=" .. given_username)

      local search_results, err = ldap.search_request(sock, {
        base = conf.base_dn;
        scope = "sub";
        filter = conf.attribute .. "=" .. given_username,
        -- Specify attribute explicitly in case it's an operational attribute,
        -- which won't be returned in the search result without being listed by name.
        -- Also can avoid retrieving not-required attributes.
        attrs = conf.group_member_attribute,
      })

      if conf.log_search_results then
        kong.log.inspect("ldap search results:")
        kong.log.inspect(search_results)
      end

      if err then
        kong.log.err("failed ldap search for "..
                     conf.attribute .. "=" .. given_username .. " base_dn=" ..
                     conf.base_dn)
        return kong.response.exit(500, { message = "An unexpected error occurred" })
      end

      kong.log.debug("finding groups with member attribute: " ..
                      conf.group_member_attribute)

      local user_dn, search_result
      for dn, result in pairs(search_results) do
        if user_dn then
          kong.log.err("more than one user found in ldap_search with" ..
                       " attribute = " .. conf.attribute ..
                       " and given_username=" .. given_username)
          return kong.response.exit(500)
        end

        user_dn = dn
        search_result = result
      end

      if not user_dn then
        return false, nil, "User not found"
      end

      is_authenticated, err = ldap.bind_request(sock, user_dn, given_password)

      if err then
        kong.log.err("bind request failed for user " .. given_username)
        return false, nil, err
      end

      if not is_authenticated then
        return false, nil, nil
      end

      local raw_groups = search_result[conf.group_member_attribute]
      local groups_required = conf.groups_required
      if raw_groups and #raw_groups then
        kong.log.debug("found groups")

        local group_dn = conf.group_base_dn or conf.base_dn
        local group_attr = conf.group_name_attribute or conf.attribute

        groups = ldap_groups.validate_groups(raw_groups, group_dn, group_attr)
        ldap_groups.set_groups(groups)

        if groups == nil then
          kong.log.debug("user has groups, but they are invalid. " ..
                 "group must include group_base_dn with group_name_attribute")
        end

        if groups_required and next(groups_required) then
          local ok = check_group_membership(conf, groups)
          if not ok then
            return kong.response.exit(403, {
              message = "User not in authorized LDAP Group"
            })
          end
        end
      else
        kong.log.debug("did not find groups for ldap search result")
        clear_header(constants.HEADERS.AUTHENTICATED_GROUPS)

        if groups_required and next(groups_required) then
          return kong.response.exit(403, {
            message = "User not in authorized LDAP Group"
          })
        end
      end
    end
  else
    kong.log.debug("bind_dn failed to bind with given ldap_password," ..
      "attempting to bind with username and base_dn:",
      conf.attribute .. "=" .. given_username .. "," .. conf.base_dn)
    local who = conf.attribute .. "=" .. given_username .. "," .. conf.base_dn
    is_authenticated, err = ldap.bind_request(sock, who, given_password)
  end

  ok, suppressed_err = sock:setkeepalive(conf.keepalive)
  if not ok then
    kong.log.err("failed to keepalive to ", conf.ldap_host, ":",
                 tostring(conf.ldap_port), ": ", suppressed_err)
  end
  return is_authenticated, groups, err
end

local function load_credential(given_username, given_password, conf)
  local ok, groups, err = ldap_authenticate(given_username, given_password, conf)
  if err ~= nil then
    kong.log.err(err)
  end

  if ok == nil then
    return nil
  end
  if ok == false then
    return false
  end
  return {username = given_username, password = given_password, groups = groups}
end


local function cache_key(conf, username, password)
  local err
  if not ldap_config_cache[conf] then
    ldap_config_cache[conf], err = sha256_hex(fmt("%s:%u:%s:%s:%u",
      lower(conf.ldap_host),
      conf.ldap_port,
      conf.base_dn,
      conf.attribute,
      conf.cache_ttl
    ))
  end

  if err then
    return nil, err
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

  local cache_key, err = cache_key(conf, given_username, given_password)
  local credential
  if cache_key then
    credential, err = kong.cache:get(cache_key, {
      ttl = conf.cache_ttl,
      neg_ttl = conf.cache_ttl
    }, load_credential, given_username, given_password, conf)
  end

  if err or credential == nil then
    return kong.response.exit(500, err)
  end

  return credential and credential.password == given_password, credential
end


-- in case of auth plugins concatenation, remove remnants of anonymous
local function remove_headers(consumer)
  ngx.ctx.authenticated_consumer = nil
  ngx_set_header(constants.HEADERS.ANONYMOUS, nil)

  if not consumer then
    ngx_set_header(constants.HEADERS.CONSUMER_ID, nil)
    ngx_set_header(constants.HEADERS.CONSUMER_CUSTOM_ID, nil)
    ngx_set_header(constants.HEADERS.CONSUMER_USERNAME, nil)
  end
end


local function set_consumer(consumer, credential, anonymous)
  if credential then
    ngx_set_header(constants.HEADERS.CREDENTIAL_IDENTIFIER, credential.username)
    ngx.ctx.authenticated_credential = credential
  end

  if consumer and not anonymous then
    ngx_set_header(constants.HEADERS.CONSUMER_ID, consumer.id)
    ngx_set_header(constants.HEADERS.CONSUMER_CUSTOM_ID, consumer.custom_id)
    ngx_set_header(constants.HEADERS.CONSUMER_USERNAME, consumer.username)
    remove_headers(consumer)

    ngx.ctx.authenticated_consumer = consumer
    return
  end

  if consumer and anonymous then
    ngx_set_header(constants.HEADERS.CONSUMER_ID, consumer.id)
    ngx_set_header(constants.HEADERS.CONSUMER_CUSTOM_ID, consumer.custom_id)
    ngx_set_header(constants.HEADERS.CONSUMER_USERNAME, consumer.username)
    ngx_set_header(constants.HEADERS.ANONYMOUS, true)
    ngx.ctx.authenticated_consumer = consumer
    return
  end

  remove_headers()
end


local function find_consumer(consumer_field, value)
  local result, err
  local dao = kong.db.consumers

  if consumer_field == "id" then
    result, err = dao:select({ id = value })
  else
     result, err = dao["select_by_" .. consumer_field](dao, value)
  end

  if err then
    kong.log.debug("failed to load consumer", err)
    return
  end

  return result
end


local function load_consumers(value, consumer_by)
  local err

  if not value then
    return nil, "cannot load consumers with empty value"
  end

  for _, field_name in ipairs(consumer_by) do
    local key
    local consumer

    if field_name == "id" then
      key = kong.db.consumers:cache_key(value)
    else
      key = ldap_cache.consumer_field_cache_key(field_name, value)
    end

    consumer, err = kong.cache:get(key, nil, find_consumer, field_name, value)

    if consumer then
      return consumer
    end
  end

  return nil, err
end


local function do_authentication(conf)
  local headers = request.get_headers()
  local authorization_value = headers[AUTHORIZATION]
  local proxy_authorization_value = headers[PROXY_AUTHORIZATION]
  local anonymous = conf.anonymous
  local consumer, err

  -- If both headers are missing, check anonymous
  if not (authorization_value or proxy_authorization_value) then
    local scheme = conf.header_type
    if scheme == "ldap" then
       -- RFC 7617 says auth-scheme is case-insentitive
       -- ensure backwards compatibility (see GH PR #3656)
      scheme = upper(scheme)
    end
    ngx.header["WWW-Authenticate"] = scheme .. ' realm="kong"'

    if anonymous ~= "" then
      local consumer_cache_key = kong.db.consumers:cache_key(anonymous)
      consumer, err = kong.cache:get(consumer_cache_key, nil,
                                          kong.client.load_consumer,
                                          anonymous, true)
    end

    if err then
      kong.log.err('error fetching anonymous user with conf.anonymous="' ..
                   (anonymous or '') .. '"', err)
      return false, { status = 500, message = "An unexpected error occurred" }
    end

    if consumer then
      set_consumer(consumer, nil, anonymous)
      return true
    end

    -- anonymous is configured but doesn't exist
    if anonymous ~= "" and not consumer then
      kong.log.err('anonymous user not found with conf.anonymous="' ..
                   (anonymous or '') .. '"', err)
      return false, { status = 500, message = "An unexpected error occurred" }
    end

    return false, { status = 401, message = "Unauthorized" }
  end

  local is_authorized, credential = authenticate(conf, proxy_authorization_value)
  if not is_authorized then
    is_authorized, credential = authenticate(conf, authorization_value)
  end

  if not is_authorized then
    if anonymous ~= "" then
      local consumer_cache_key = kong.db.consumers:cache_key(anonymous)
      consumer, err = kong.cache:get(consumer_cache_key, nil,
                                     kong.client.load_consumer,
                                     anonymous, true)
    end

    if consumer then
      set_consumer(consumer, credential, anonymous)
      return true
    end

    if err then
      kong.log.err("load consumer error when 'not authorized' ", err)
      return false, { status = 500, message = "An unexpected error occurred" }
    end

    return false, { status = 401, message = "Unauthorized" }
  end

  if conf.hide_credentials then
    request.clear_header(AUTHORIZATION)
    request.clear_header(PROXY_AUTHORIZATION)
  end

  if not conf.consumer_optional then
    kong.log.debug('consumer mapping is not optional, looking for consumer.')
    consumer, err = load_consumers(credential.username, conf.consumer_by)

    if not consumer then
      kong.log.debug("consumer not found, checking anonymous")
      if err then
        kong.log.err("load consumer error when not 'conf.consumer_optional'", err)
        return false, { status = 500, message = "An unexpected error occurred" }
      end

      if anonymous ~= "" then
        local consumer_cache_key = kong.db.consumers:cache_key(anonymous)
        consumer, err = kong.cache:get(consumer_cache_key, nil,
                                            kong.client.load_consumer,
                                            anonymous, true)
      end
      if err then
        kong.log.err("load anonymous consumer error", err)
        return false, { status = 500, message = "An unexpected error occurred" }
      end

    else
      -- we found a consumer to map, so no need to fallback to anonymous
      kong.log.debug("consumer found, id:", consumer.id)
      anonymous = nil
    end
  end

  ldap_groups.set_groups(credential.groups)
  set_consumer(consumer, credential, anonymous)

  return true
end


function _M.execute(conf)
  if ngx.ctx.authenticated_credential and conf.anonymous ~= "" then
    -- we're already authenticated, and we're configured for using anonymous,
    -- hence we're in a logical OR between auth methods and we're already done.
    kong.log.debug("credential found, using anonymous consumer:", conf.anonymous)
    return
  end

  local ok, err = do_authentication(conf)
  if not ok then
    return kong.response.exit(err.status, { message = err.message })
  end
end


return _M
