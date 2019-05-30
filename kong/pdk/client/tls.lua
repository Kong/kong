---
-- The client.tls module provides functions for interacting with TLS
-- connections from client.
--
-- @module kong.client.tls


local phase_checker = require "kong.pdk.private.phases"
local kong_tls = require "resty.kong.tls"


local check_phase = phase_checker.check


local PHASES = phase_checker.phases
local REWRITE_AND_LATER = phase_checker.new(PHASES.rewrite,
                                            PHASES.access,
                                            PHASES.balancer,
                                            PHASES.header_filter,
                                            PHASES.body_filter,
                                            PHASES.log)


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


  return _TLS
end


return {
  new = new,
}
