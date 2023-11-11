local _M = {}
local _MT = { __index = _M, }


local kong = kong


local utils       = require("kong.router.utils")


local phonehome_statistics = utils.phonehome_statistics


_M.DEFAULT_MATCH_LRUCACHE_SIZE = utils.DEFAULT_MATCH_LRUCACHE_SIZE


local FLAVOR_TO_MODULE = {
  traditional            = "kong.router.traditional",
  expressions            = "kong.router.expressions",
  traditional_compatible = "kong.router.compat",
}


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
                 kong.configuration.router_flavor or
                 "traditional"

  local router = require(FLAVOR_TO_MODULE[flavor])

  phonehome_statistics(routes)

  if flavor == "traditional" then
    local trad, err = router.new(routes, cache, cache_neg)
    if not trad then
      return nil, err
    end

    return setmetatable({
      trad = trad,
      _set_ngx = trad._set_ngx, -- for unit-testing only
    }, _MT)
  end

  -- flavor == "expressions" or "traditional_compatible"
  return router.new(routes, cache, cache_neg, old_router)
end


return _M
