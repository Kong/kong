---
-- The client.tls module provides functions for interacting with TLS
-- connections from client.
--
-- @module kong.client.tls


local phase_checker = require "kong.pdk.private.phases"
local kong_tls = require "resty.kong.tls"


local check_phase = phase_checker.check
local error = error
local type = type
local ngx = ngx


local PHASES = phase_checker.phases
local REWRITE_AND_LATER = phase_checker.new(PHASES.rewrite,
                                            PHASES.access,
                                            PHASES.balancer,
                                            PHASES.log)
local REWRITE_BEFORE_LOG = phase_checker.new(PHASES.rewrite,
                                             PHASES.access,
                                             PHASES.balancer)


local function new()
  local _TLS = {}


  ---
  -- Requests client to present its client-side certificate to initiate mutual
  -- TLS authentication between server and client.
  --
  -- This function only *requests*, but does not *require* the client to start
  -- the mTLS process. Even if the client did not present a client certificate
  -- the TLS handshake will still complete (obviously not being mTLS in that
  -- case). Whether the client honored the request can be determined using
  -- get_full_client_certificate_chain in later phases.
  --
  -- @function kong.client.tls.request_client_certificate
  -- @phases certificate
  -- @treturn true|nil true if request was received, nil if request failed
  -- @treturn nil|err nil if success, or error message if failure
  --
  -- @usage
  -- local res, err = kong.client.tls.request_client_certificate()
  -- if not res then
  --   -- do something with err
  -- end
  function _TLS.request_client_certificate()
    check_phase(PHASES.certificate)

    return kong_tls.request_client_certificate()
  end


  ---
  -- Prevents the TLS session for the current connection from being reused
  -- by disabling session ticket and session ID for the current TLS connection.
  --
  -- @function kong.client.tls.disable_session_reuse
  -- @phases certificate
  -- @treturn true|nil true if success, nil if failed
  -- @treturn nil|err nil if success, or error message if failure
  --
  -- @usage
  -- local res, err = kong.client.tls.disable_session_reuse()
  -- if not res then
  --   -- do something with err
  -- end
  function _TLS.disable_session_reuse()
    check_phase(PHASES.certificate)

    return kong_tls.disable_session_reuse()
  end


  ---
  -- Returns the PEM encoded downstream client certificate chain with the
  -- client certificate at the top and intermediate certificates
  -- (if any) at the bottom.
  --
  -- @function kong.client.tls.get_full_client_certificate_chain
  -- @phases rewrite, access, balancer, header_filter, body_filter, log
  -- @treturn string|nil PEM-encoded client certificate if mTLS handshake
  -- was completed, nil if an error occurred or client did not present
  -- its certificate
  -- @treturn nil|err nil if success, or error message if failure
  --
  -- @usage
  -- local cert, err = kong.client.get_full_client_certificate_chain()
  -- if err then
  --   -- do something with err
  -- end
  --
  -- if not cert then
  --   -- client did not complete mTLS
  -- end
  --
  -- -- do something with cert
  function _TLS.get_full_client_certificate_chain()
    check_phase(REWRITE_AND_LATER)

    return kong_tls.get_full_client_certificate_chain()
  end



  ---
  -- Overrides client verify result generated by the log serializer.
  --
  -- By default, the `request.tls.client_verify` field inside the log
  -- generated by Kong's log serializer is the same as the
  -- [$ssl_client_verify](https://nginx.org/en/docs/http/ngx_http_ssl_module.html#var_ssl_client_verify)
  -- Nginx variable.
  --
  -- This function does not return anything on success, and throws an Lua error
  -- in case of failures.
  --
  -- @function kong.client.tls.set_client_verify
  -- @phases rewrite, access, balancer
  --
  -- @usage
  -- kong.client.tls.set_client_verify("FAILED:unknown CA")
  function _TLS.set_client_verify(v)
    check_phase(REWRITE_BEFORE_LOG)

    assert(type(v) == "string")

    if v ~= "SUCCESS" and v ~= "NONE" and v:sub(1, 7) ~= "FAILED:" then
      error("unknown client verify value: " .. tostring(v) ..
            " accepted values are: \"SUCCESS\", \"NONE\"" ..
            " or \"FAILED:<reason>\"", 2)
    end

    ngx.ctx.CLIENT_VERIFY_OVERRIDE = v
  end


  return _TLS
end


return {
  new = new,
}
