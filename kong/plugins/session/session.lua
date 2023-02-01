local kong_storage = require "kong.plugins.session.storage.kong"
local resty_session = require "resty.session"


local kong = kong
local ipairs = ipairs


local _M = {}


--- Open a session based on plugin config
-- @returns resty.session session object
function _M.open_session(conf)
  kong.log.inspect(conf.response_headers)

  return resty_session.open({
    secret                    = conf.secret,
    audience                  = conf.audience,
    storage                   = conf.storage == "kong" and kong_storage,
    idling_timeout            = conf.idling_timeout,
    rolling_timeout           = conf.rolling_timeout,
    absolute_timeout          = conf.absolute_timeout,
    stale_ttl                 = conf.stale_ttl,
    cookie_name               = conf.cookie_name,
    cookie_path               = conf.cookie_path,
    cookie_domain             = conf.cookie_domain,
    cookie_same_site          = conf.cookie_same_site,
    cookie_http_only          = conf.cookie_http_only,
    cookie_secure             = conf.cookie_secure,
    remember                  = conf.remember,
    remember_cookie_name      = conf.remember_cookie_name,
    remember_rolling_timeout  = conf.remember_rolling_timeout,
    remember_absolute_timeout = conf.remember_absolute_timeout,
    response_headers          = conf.response_headers,
    request_headers           = conf.request_headers,
  })
end


--- Gets consumer id and credential id from the session data
-- @param session - the session
-- @returns consumer_id, credential_id, groups
function _M.get_session_data(session)
  if not session then
    return
  end

  local data = session:get_data()
  if not data then
    return
  end

  return data[1], data[2], data[3]
end


--- Store the session data for usage in kong plugins
-- @param session - the session
-- @param consumer_id - the consumer id
-- @param credential_id - the credential id or potentially just the consumer id
-- @param groups - table of authenticated_groups e.g. { "group1" }
function _M.set_session_data(session, consumer_id, credential_id, groups)
  if not session then
    return
  end

  session:set_data({
    consumer_id,
    credential_id,
    groups,
  })
end


--- Determine is incoming request is trying to logout
-- @return boolean should logout of the session?
function _M.logout(conf)
  local logout_methods = conf.logout_methods
  if not logout_methods then
    return false
  end

  local request_method = kong.request.get_method()
  local logout
  for _, logout_method in ipairs(logout_methods) do
    if logout_method == request_method then
      logout = true
      break
    end
  end

  if not logout then
    return false
  end

  local logout_query_arg = conf.logout_query_arg
  if logout_query_arg then
    if kong.request.get_query_arg(logout_query_arg) then
      kong.log.debug("logout by query argument")
      return true
    end
  end

  local logout_post_arg = conf.logout_post_arg
  if logout_post_arg then
    local post_args = kong.request.get_body()
    if post_args and post_args[logout_post_arg] then
      kong.log.debug("logout by post argument")
      return true
    end
  end

  return false
end


return _M
