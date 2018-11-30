local session = require "resty.session"

local _M = {}


function get_opts(conf)
  return {
    name = conf.cookie_name or "session",
    random = { random = { length = 32 } },
    cookie = {
      lifetime = conf.cookie_lifetime,
      path     = conf.cookie_path,
      domain   = conf.cookie_domain,
      samesite = conf.cookie_samesite,
      httponly = conf.cookie_httponly,
      secure   = conf.cookie_secure,
    },
  }
end


function _M.open_session(conf)
  local opts = get_opts(conf)
  local sesh = session.open(opts)

  if sesh.present then
    return sesh
  end

  if not sesh.started then
    sesh:start()
  end

  sesh:save()

  return sesh
end


return _M
