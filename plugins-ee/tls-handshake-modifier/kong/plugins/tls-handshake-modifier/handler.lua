-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

--- Copyright 2019 Kong Inc.

local ngx = ngx
local kong = kong
local kong_global = require("kong.global")
local PHASES = kong_global.phases

local certificate = require("kong.enterprise_edition.tls.plugins.certificate")
local sni_filter = require("kong.enterprise_edition.tls.plugins.sni_filter")
local tls_cache = require("kong.plugins.tls-handshake-modifier.cache")
local meta = require "kong.meta"

local TTL_FOREVER = { ttl = 0 }
local SNI_CACHE_KEY = tls_cache.SNI_CACHE_KEY

local TLSHandshakeModifier = {
  -- execute before the tls-metadata-headers plugin
  PRIORITY = 997,
  VERSION = meta.core_version
}

local plugin_name = "tls-handshake-modifier"

function TLSHandshakeModifier:access(conf)

end

function TLSHandshakeModifier:init_worker()
  -- TODO: remove nasty hacks once we have singleton phases support in core

  local orig_ssl_certificate = Kong.ssl_certificate   -- luacheck: ignore
  Kong.ssl_certificate = function()                   -- luacheck: ignore
    orig_ssl_certificate()

    local ctx = ngx.ctx
    -- ensure phases are set
    ctx.KONG_PHASE = PHASES.certificate

    kong_global.set_namespaced_log(kong, plugin_name)
    local snis_set, err = kong.cache:get(SNI_CACHE_KEY, TTL_FOREVER,
    sni_filter.build_ssl_route_filter_set, plugin_name)

    if err then
      kong.log.err("unable to request client to present its certificate: ",
            err)
      return ngx.exit(ngx.ERROR)
    end
    certificate.execute(snis_set)
    kong_global.reset_log(kong)

  end

  tls_cache.init_worker()

end

return TLSHandshakeModifier
