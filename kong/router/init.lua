local _M = {}
local _MT = { __index = _M, }


local kong = kong


local traditional = require("kong.router.traditional")
local expressions = require("kong.router.expressions")
local utils       = require("kong.router.utils")


local compat
if ngx.config.subsystem == "http" then
  compat = require("kong.router.compat")
else
  compat = require("kong.router.compat_stream")
end

local phonehome_statistics = utils.phonehome_statistics


_M.DEFAULT_MATCH_LRUCACHE_SIZE = utils.DEFAULT_MATCH_LRUCACHE_SIZE


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


function _M.new(routes, cache, cache_neg, old_router)
  local flavor = kong and
                 kong.configuration and
                 kong.configuration.router_flavor

  phonehome_statistics(routes)

  if not flavor or flavor == "traditional" then

    local trad, err = traditional.new(routes, cache, cache_neg)
    if not trad then
      return nil, err
    end

    return setmetatable({
      trad = trad,
    }, _MT)
  end

  if flavor == "expressions" then
    return expressions.new(routes, cache, cache_neg, old_router)
  end

  -- flavor == "traditional_compatible"
  return compat.new(routes, cache, cache_neg, old_router)
end


_M._set_ngx = traditional._set_ngx
_M.split_port = traditional.split_port


return _M
