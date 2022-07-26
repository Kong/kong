local _M = {}

local kong = kong

local traditional = require("kong.router.traditional")
local atc_compat = require("kong.router.atc_compat")
local is_http = ngx.config.subsystem == "http"


local _MT = { __index = _M, }


local function is_traditional()
  return not is_http or
         not kong or
         not kong.configuration or
         kong.configuration.router_flavor == "traditional"
end


function _M:exec(ctx)
  return self.trad.exec(ctx)
end


function _M:select(req_method, req_uri, req_host, req_scheme,
                   src_ip, src_port,
                   dst_ip, dst_port,
                   sni, req_headers)
  return self.trad.select(req_method, req_uri, req_host, req_scheme,
                          src_ip, src_port,
                          dst_ip, dst_port,
                          sni, req_headers)
end


function _M.new(routes, cache, cache_neg)
  if is_traditional() then
    local trad, err = traditional.new(routes, cache, cache_neg)
    if not trad then
      return nil, err
    end

    return setmetatable({
      trad = trad,
    }, _MT)
  end

  return atc_compat.new(routes)
end


_M._set_ngx = traditional._set_ngx
_M.split_port = traditional.split_port


if is_traditional() then
  _M.MATCH_LRUCACHE_SIZE = traditional.MATCH_LRUCACHE_SIZE or 0
else
  _M.MATCH_LRUCACHE_SIZE = atc_compat.MATCH_LRUCACHE_SIZE or 0
end


return _M
