local storage = require "kong.plugins.session.storage.kong"
local session = require "resty.session"


local kong = kong
local ipairs = ipairs


local _M = {}


local function get_opts(conf)
  return {
    name = conf.cookie_name,
    secret = conf.secret,
    cookie = {
      lifetime = conf.cookie_lifetime,
      path     = conf.cookie_path,
      domain   = conf.cookie_domain,
      samesite = conf.cookie_samesite,
      httponly = conf.cookie_httponly,
      secure   = conf.cookie_secure,
      renew    = conf.cookie_renew,
      discard  = conf.cookie_discard,
    }
  }
end


--- Open a session based on plugin config
-- @returns resty.session session object
function _M.open_session(conf)
  local opts = get_opts(conf)
  local s

  if conf.storage == 'kong' then
    -- Required strategy for kong adapter which will allow for :regenerate
    -- method to keep sessions around during renewal period to allow for
    -- concurrent requests. When client exchanges cookie for new cookie,
    -- old sessions will have their ttl updated, which will discard the item
    -- after "cookie_discard" period.
    opts.strategy = "regenerate"
    s = session.new(opts)
    s.storage = storage.new(s)
    s:open()
  else
    opts.storage = conf.storage
    s = session.open(opts)
  end

  return s
end


--- Gets consumer id and credential id from the session data
-- @param s - the session
-- @returns consumer_id, credential_id
function _M.retrieve_session_data(s)
  if not s then return nil, nil end

  if s and not s.data then
    return nil, nil
  end

  return s.data[1], s.data[2]
end


--- Store the session data for usage in kong plugins
-- @param s - the session
-- @param consumer - the consumer id
-- @param credential - the credential id or potentially just the consumer id
function _M.store_session_data(s, consumer_id, credential_id)
  if not s then
    return
  end

  s.data[1] = consumer_id
  s.data[2] = credential_id
end


--- Determine is incoming request is trying to logout
-- @return boolean should logout of the session?
function _M.logout(conf)
  local logout = false

  local logout_methods = conf.logout_methods
  if logout_methods then
    local request_method = kong.request.get_method()
    for _, logout_method in ipairs(logout_methods) do
      if logout_method == request_method then
        logout = true
        break
      end
    end
    if logout then
      logout = false

      local logout_query_arg = conf.logout_query_arg
      if logout_query_arg then
        local uri_args = kong.request.get_query()
        if uri_args[logout_query_arg] then
          logout = true
        end
      end

      if logout then
        kong.log.debug("logout by query argument")
      else
        local logout_post_arg = conf.logout_post_arg
        if logout_post_arg then
          ngx.req.read_body()
          local post_args = ngx.req.get_post_args()
          if post_args[logout_post_arg] then
            logout = true
          end

          if logout then
            kong.log.debug("logout by post argument")
          end
        end
      end
    end
  end

  return logout
end


return _M
