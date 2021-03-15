---
-- The service module contains a set of functions to manipulate the connection
-- aspect of the request to the Service, such as connecting to a given host, IP
-- address/port, or choosing a given Upstream entity for load-balancing and
-- healthchecking.
--
-- @module kong.service


local balancer = require "kong.runloop.balancer"
local phase_checker = require "kong.pdk.private.phases"


local ngx = ngx
local check_phase = phase_checker.check


local PHASES = phase_checker.phases
local access_and_rewrite_and_balancer =
    phase_checker.new(PHASES.rewrite, PHASES.access, PHASES.balancer)


local function new()
  local service = {}


  ---
  -- Sets the desired Upstream entity to handle the load-balancing step for
  -- this request. Using this method is equivalent to creating a Service with a
  -- `host` property equal to that of an Upstream entity (in which case, the
  -- request would be proxied to one of the Targets associated with that
  -- Upstream).
  --
  -- The `host` argument should receive a string equal to that of one of the
  -- Upstream entities currently configured.
  --
  -- @function kong.service.set_upstream
  -- @phases access
  -- @tparam string host
  -- @treturn boolean|nil `true` on success, or `nil` if no upstream entities
  -- where found
  -- @treturn string|nil An error message describing the error if there was
  -- one.
  --
  -- @usage
  -- local ok, err = kong.service.set_upstream("service.prod")
  -- if not ok then
  --   kong.log.err(err)
  --   return
  -- end
  function service.set_upstream(host)
    check_phase(PHASES.access)

    if type(host) ~= "string" then
      error("host must be a string", 2)
    end

    local upstream = balancer.get_upstream_by_name(host)
    if not upstream then
      return nil, "could not find an Upstream named '" .. host .. "'"
    end

    ngx.ctx.balancer_data.host = host
    return true
  end


  ---
  -- Sets the host and port on which to connect to for proxying the request.
  -- Using this method is equivalent to ask Kong to not run the load-balancing
  -- phase for this request, and consider it manually overridden.
  -- Load-balancing components such as retries and health-checks will also be
  -- ignored for this request.
  --
  -- The `host` argument expects a string containing the IP address of the
  -- upstream server (IPv4/IPv6), and the `port` argument must contain a number
  -- representing the port on which to connect to.
  --
  -- @function kong.service.set_target
  -- @phases access
  -- @tparam string host
  -- @tparam number port
  -- @usage
  -- kong.service.set_target("service.local", 443)
  -- kong.service.set_target("192.168.130.1", 80)
  function service.set_target(host, port)
    check_phase(PHASES.access)

    if type(host) ~= "string" then
      error("host must be a string", 2)
    end
    if type(port) ~= "number" or math.floor(port) ~= port then
      error("port must be an integer", 2)
    end
    if port < 0 or port > 65535 then
      error("port must be an integer between 0 and 65535: given " .. port, 2)
    end

    ngx.var.upstream_host = host

    local ctx = ngx.ctx
    ctx.balancer_data.host = host
    ctx.balancer_data.port = port
  end


  if ngx.config.subsystem == "http" then
    local tls = require("resty.kong.tls")

    local set_upstream_cert_and_key = tls.set_upstream_cert_and_key
    local set_upstream_ssl_verify = tls.set_upstream_ssl_verify
    local set_upstream_ssl_verify_depth = tls.set_upstream_ssl_verify_depth
    local set_upstream_ssl_trusted_store = tls.set_upstream_ssl_trusted_store

    ---
    -- Sets the client certificate used while handshaking with the Service.
    --
    -- The `chain` argument is the client certificate and intermediate chain (if any)
    -- returned by functions such as [ngx.ssl.parse\_pem\_cert](https://github.com/openresty/lua-resty-core/blob/master/lib/ngx/ssl.md#parse_pem_cert).
    --
    -- The `key` argument is the private key corresponding to the client certificate
    -- returned by functions such as [ngx.ssl.parse\_pem\_priv\_key](https://github.com/openresty/lua-resty-core/blob/master/lib/ngx/ssl.md#parse_pem_priv_key).
    --
    -- @function kong.service.set_tls_cert_key
    -- @phases `rewrite`, `access`, `balancer`
    -- @tparam cdata chain The client certificate chain
    -- @tparam cdata key The client certificate private key
    -- @treturn boolean|nil `true` if the operation succeeded, `nil` if an error occurred
    -- @treturn string|nil An error message describing the error if there was one
    -- @usage
    -- local chain = assert(ssl.parse_pem_cert(cert_data))
    -- local key = assert(ssl.parse_pem_priv_key(key_data))
    --
    -- local ok, err = kong.service.set_tls_cert_key(chain, key)
    -- if not ok then
    --   -- do something with error
    -- end
    service.set_tls_cert_key = function(chain, key)
      check_phase(access_and_rewrite_and_balancer)

      if type(chain) ~= "cdata" then
        error("chain must be a parsed cdata object", 2)
      end

      if type(key) ~= "cdata" then
        error("key must be a parsed cdata object", 2)
      end

      local res, err = set_upstream_cert_and_key(chain, key)
      return res, err
    end


    ---
    -- Sets whether TLS verification is enabled while handshaking with the Service.
    --
    -- The `on` argument is a boolean flag, where `true` means upstream verification
    -- is enabled and `false` disables it.
    --
    -- This call affects only the current request. If the trusted certificate store is
    -- not set already (via [proxy_ssl_trusted_certificate](https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_ssl_trusted_certificate)
    -- or [kong.service.set_upstream_ssl_trusted_store](#kongserviceset_upstream_ssl_trusted_store)),
    -- then TLS verification will always fail with "unable to get local issuer certificate" error.
    --
    -- @function kong.service.set_tls_verify
    -- @phases `rewrite`, `access`, `balancer`
    -- @tparam boolean on Whether to enable TLS certificate verification for the current request
    -- @treturn boolean|nil `true` if the operation succeeded, `nil` if an error occurred
    -- @treturn string|nil An error message describing the error if there was one
    -- @usage
    -- local ok, err = kong.service.set_tls_verify(true)
    -- if not ok then
    --   -- do something with error
    -- end
    service.set_tls_verify = function(on)
      check_phase(access_and_rewrite_and_balancer)

      if type(on) ~= "boolean" then
        error("argument must be a boolean", 2)
      end

      return set_upstream_ssl_verify(on)
    end


    ---
    -- Sets the maximum depth of verification when validating upstream server's TLS certificate.
    --
    -- This call affects only the current request. For the depth to be actually used the verification
    -- has to be enabled with either the [proxy_ssl_verify](https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_ssl_verify)
    -- directive or using the [kong.service.set_tls_verify](#kongserviceset_tls_verify) function.
    --
    -- @function kong.service.set_tls_verify_depth
    -- @phases `rewrite`, `access`, `balancer`
    -- @tparam number depth Depth to use when validating. Must be non-negative
    -- @treturn boolean|nil `true` if the operation succeeded, `nil` if an error occurred
    -- @treturn string|nil An error message describing the error if there was one
    -- @usage
    -- local ok, err = kong.service.set_tls_verify_depth(3)
    -- if not ok then
    --   -- do something with error
    -- end
    service.set_tls_verify_depth = function(depth)
      check_phase(access_and_rewrite_and_balancer)

      if type(depth) ~= "number" then
        error("argument must be a number", 2)
      end

      return set_upstream_ssl_verify_depth(depth)
    end


    ---
    -- Sets the CA trust store to use when validating upstream server's TLS certificate.
    --
    -- This call affects only the current request. For the store to be actually used the verification
    -- has to be enabled with either the [proxy_ssl_verify](https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_ssl_verify)
    -- directive or using the [kong.service.set_tls_verify](#kongserviceset_tls_verify) function.
    --
    -- The resty.openssl.x509.store object can be created by following
    -- [examples](https://github.com/Kong/lua-kong-nginx-module#restykongtlsset_upstream_ssl_trusted_store) from the Kong/lua-kong-nginx-module repo.
    --
    -- @function kong.service.set_tls_verify_store
    -- @phases `rewrite`, `access`, `balancer`
    -- @tparam table store resty.openssl.x509.store object to use
    -- @treturn boolean|nil `true` if the operation succeeded, `nil` if an error occurred
    -- @treturn string|nil An error message describing the error if there was one
    -- @usage
    -- local store = require("resty.openssl.x509.store")
    -- local st = assert(store.new())
    -- -- st:add(...certificate)
    --
    -- local ok, err = kong.service.set_tls_verify_store(st)
    -- if not ok then
    --   -- do something with error
    -- end
    service.set_tls_verify_store = function(store)
      check_phase(access_and_rewrite_and_balancer)

      if type(store) ~= "table" then
        error("argument must be a resty.openssl.x509.store object", 2)
      end

      return set_upstream_ssl_trusted_store(store)
    end
  end


  return service
end


return {
  new = new,
}
