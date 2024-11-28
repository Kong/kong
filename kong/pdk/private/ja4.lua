-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local phase_checker = require "kong.pdk.private.phases"
local kong_tls = require "resty.kong.tls"
local ja4 = require "kong.enterprise_edition.tls.ja4"

local band = require("bit").band
local check_phase = phase_checker.check


local PHASES = phase_checker.phases
local CERTIFICATE_AND_LATER = phase_checker.new(PHASES.certificate,
                                                PHASES.rewrite,
                                                PHASES.access,
                                                PHASES.response,
                                                PHASES.header_filter,
                                                PHASES.body_filter,
                                                PHASES.balancer,
                                                PHASES.log)

local _M = {}


function _M.compute_client_ja4()
  check_phase(PHASES.client_hello)

  if ngx.config.subsystem ~= "http" then
    return nil, "Not in HTTP module"
  end

  local tls_connection, err = kong_tls.get_request_ssl_pointer()
  if not tls_connection then
    return nil, err
  end

  local fingerprint, err = ja4.compute_ja4_fingerprint(tls_connection)
  if not fingerprint then
    return nil, err
  end

  ngx.ctx.ja4_fingerprint = fingerprint

  return true
end


function _M.get_computed_client_ja4()
  check_phase(CERTIFICATE_AND_LATER)

  if not ngx.ctx.ja4_fingerprint then
    local ja4_fingerprint, stale = ja4.get_fingerprint_from_cache(ngx.var.connection)
    ja4_fingerprint = ja4_fingerprint or stale

    if not ja4_fingerprint then
      return nil, "JA4 fingerprint not generated"
    end

    ngx.ctx.ja4_fingerprint = ja4_fingerprint
  end

  if ngx.ctx.KONG_PHASE and band(ngx.ctx.KONG_PHASE, CERTIFICATE_AND_LATER) ~= 0 then
    ja4.set_fingerprint_to_cache(ngx.var.connection, ngx.ctx.ja4_fingerprint)
  end

  return ngx.ctx.ja4_fingerprint
end


return _M
