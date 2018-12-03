local session = require "resty.session"

local _M = {}


local function get_opts(conf)
  return {
    name = conf.cookie_name,
    storage = conf.storage,
    cookie = {
      lifetime = conf.cookie_lifetime,
      path     = conf.cookie_path,
      domain   = conf.cookie_domain,
      samesite = conf.cookie_samesite,
      httponly = conf.cookie_httponly,
      secure   = conf.cookie_secure,
    }
  }
end


function _M.open_session(conf)
  local opts = get_opts(conf)
  local s = session.open(opts)

  if s.present then
    return s
  end

  if not s.started then
    s:start()
  end

  return s
end


return _M
