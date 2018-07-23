local http_tls = require "http.tls"
local openssl_pkey = require "openssl.pkey"
local openssl_ssl = require "openssl.ssl"
local openssl_store = require "openssl.x509.store"
local openssl_x509 = require "openssl.x509"
local getssl = require "kong.resty.getssl".getssl
local singletons = require "kong.singletons"
local Errors  = require "kong.db.errors"
local cluster_ca_tools = require "kong.tools.cluster_ca"


local encode_base64 = ngx.encode_base64


local function simple_mesh_alpn_select(ssl, protos, mesh_alpn)
  for _, v in ipairs(protos) do
    if v == mesh_alpn then
      return v
    end
  end
end


local function nginx_mesh_alpn_select(ssl, protos, mesh_server_ssl_ctx, mesh_alpn)
  -- Set verify flags back to nginx defaults
  -- See note about setting VERIFY_PEER below in certificate phase
  ssl:setVerify(ssl:getContext():getVerify())

  for _, v in ipairs(protos) do
    if v == mesh_alpn then
      -- Swap out the SSL_CTX from the nginx default one.
      -- This is the only way to change some parameters,
      -- e.g. the CA store used for verification
      ssl:setContext(mesh_server_ssl_ctx)
      -- Note: many parameters are not correctly set by the above
      -- https://github.com/openssl/openssl/issues/1652#issuecomment-384660673
      ssl:setVerify(mesh_server_ssl_ctx:getVerify()) -- to set e.g. VERIFY_FAIL_IF_NO_PEER_CERT
      return v
    -- elseif v == "h2" -- TODO: figure out if current proxy listener directive has http2 allowed
    elseif v == "http/1.1" then
      return v
    end
  end
end


local function client_hostname_callback(ssl, mesh_client_ssl_ctx, mesh_alpn)
  if ssl:getAlpnSelected() == mesh_alpn then
    ssl:setContext(mesh_client_ssl_ctx)
    -- Note: many parameters are not correctly set by the above
    -- https://github.com/openssl/openssl/issues/1652#issuecomment-384660673
    ssl:setVerify(mesh_client_ssl_ctx:getVerify())
  end
  return true
end


local mesh_alpn
local mesh_server_ssl_ctx = http_tls.new_server_context()


local function init()
  -- This should run in init phase (in master, not worker)

  ngx.log(ngx.INFO, "initialising cluster ca...")

  local ca_cert
  local node_cert
  local node_private_key
  do
    -- We need to get the CA certificate to be able to verify peers
    -- We want to generate ourselves a node certificate

    -- Try and get CA key + cert from DB
    local ca_row, err = singletons.db.cluster_ca:select({ pk = true })
    if not ca_row and err == nil then
      -- No CA cert in DB, we are the first cluster member to start

      -- Generate a CA
      local candidate_ca_key = cluster_ca_tools.new_key()
      local candidate_ca_cert = cluster_ca_tools.new_ca(candidate_ca_key)

      -- Try and add it to DB
      -- if there is a conflict, some other node beat us to it
      ca_row = {
        pk = true,
        key = candidate_ca_key:toPEM("private"),
        cert = candidate_ca_cert:toPEM(),
      }
      local ok, err_t
      ok, err, err_t = singletons.db.cluster_ca:insert(ca_row)
      if not ok then
        ca_row = nil
        if err_t.code == Errors.code.PRIMARY_KEY_VIOLATION then
          -- Another node starting up beat us, redo the query.
          ca_row, err = singletons.db.cluster_ca:select({ pk = true })
        end
      end
    end
    if not ca_row then
      error(err)
    end

    local ca_key = openssl_pkey.new(ca_row.key)
    ca_cert = openssl_x509.new(ca_row.cert)

    -- Generate our node cert
    node_private_key = cluster_ca_tools.new_key()
    local node_public_key = openssl_pkey.new(node_private_key:toPEM("public"))

    node_cert = cluster_ca_tools.new_node_cert(ca_key, ca_cert, {
      node_id = kong.node.get_id(),
      node_pub_key = node_public_key,
    })
  end -- ca_key should never leave this scope

  -- Create a unique id for *this* service mesh
  -- - Should be < 256 bytes
  -- - Should be ascii-safe
  -- - Self-identifies as Kong
  -- - Versioned in case scheme is changed later
  local cluster_id = encode_base64(ca_cert:getPublicKeyDigest("sha256"))
  mesh_alpn = "com.konghq/service-mesh/1/" .. cluster_id

  ngx.log(ngx.INFO, "cluster ca initialised")
  ngx.log(ngx.DEBUG, "mesh alpn is '", mesh_alpn, "'")
  ngx.log(ngx.DEBUG, "node certificate generated, fingerprint is '",
                     encode_base64(node_cert:getPublicKeyDigest("sha256")),
                     "'")

  local ca_store = openssl_store.new():add(ca_cert)

  if kong.default_client_ssl_ctx then
    local mesh_client_ssl_ctx = http_tls.new_client_context()
    mesh_client_ssl_ctx:setPrivateKey(node_private_key)
    mesh_client_ssl_ctx:setCertificate(node_cert)
    mesh_client_ssl_ctx:setStore(ca_store)
    -- VERIFY_PEER is already the default from lua-http

    -- Modify default ssl client context so that if our mesh alpn is accepted,
    -- swap over to use the service-mesh ssl client context.
    -- We (ab)use the OpenSSL hostname callback for doing this
    kong.default_client_ssl_ctx:setHostNameCallback(client_hostname_callback, mesh_client_ssl_ctx, mesh_alpn)
    if ngx.config.subsystem == "http" then
      kong.default_client_ssl_ctx:setAlpnProtos { mesh_alpn, "http/1.1" }
    else
      kong.default_client_ssl_ctx:setAlpnProtos { mesh_alpn }
    end
  else
    ngx.log(ngx.INFO, "Dynamic client SSL_CTX* is unavailable. mesh will not "
                   .. "be advertised for outgoing connections from this node")
  end

  mesh_server_ssl_ctx:setPrivateKey(node_private_key)
  mesh_server_ssl_ctx:setCertificate(node_cert)
  mesh_server_ssl_ctx:setStore(ca_store)
  mesh_server_ssl_ctx:setVerify(openssl_ssl.VERIFY_PEER + openssl_ssl.VERIFY_FAIL_IF_NO_PEER_CERT)
  mesh_server_ssl_ctx:setAlpnSelect(simple_mesh_alpn_select, mesh_alpn)
end


local function get_mesh_alpn()
  if mesh_alpn == nil then
    error("mesh is not initialised: missing call to runloop.mesh.init()", 2)
  end
  return mesh_alpn
end


local function certificate()
  local ssl, err = getssl()
  if not ssl then
    return nil, err
  end

  -- Replace the nginx ALPN callback for *all* requests through the current proxy_listener
  -- this callback is only way we can read the list of client proposed ALPN protocols
  local ssl_ctx = ssl:getContext()
  ssl_ctx:setAlpnSelect(nginx_mesh_alpn_select, mesh_server_ssl_ctx, mesh_alpn)
  if ssl:getVerify() < openssl_ssl.VERIFY_PEER then
    -- Need to set VERIFY_PEER here; attempting to set from the ALPN callback gives:
    -- error:14180044:SSL routines:tls_post_process_client_key_exchange:internal error
    -- We set it back to the old value in the alpn callback, but if the client
    -- didn't send an ALPN packet then this has the side-effect of allowing a
    -- client to send a cert even if nginx wasn't configured to allow it.
    -- OpenSSL will try to verify the unwanted cert; to prevent wasting CPU
    -- cycles on this unwanted verification, we set the verification depth to 0.
    ssl:setVerify(openssl_ssl.VERIFY_PEER, 0)
  end

  return true
end


local function rewrite()
  local ssl = getssl()
  if ssl and ssl:getAlpnSelected() == mesh_alpn then
    if ngx.ctx.is_service_mesh_request then
      ngx.log(ngx.ERR, "already service mesh; circular routing?")
      return ngx.exit(500)
    end

    -- Assume OpenSSL verification worked
    ngx.ctx.is_service_mesh_request = true

    -- Fixup Host
    -- Unless the route had preserve_host set then the host on the request has
    -- been transformed to host of the peer's target or service.
    -- We rely on the X-Forwarded-Host header to transform it back
    -- As this is a secured service-mesh connection we can assume that the peer
    -- Kong node has set it (as it's not optional).
    -- XXX: The one exception would be if a plugin on the peer has modified it
    local original_host = ngx.var.http_x_forwarded_host
    assert(original_host, "missing X-Forwarded-Host")
    -- We can't set ngx.var.http_host, but ngx.req.set_header seems to work
    ngx.req.set_header("host", original_host)
  end
end


return {
  init = init,
  get_mesh_alpn = get_mesh_alpn,
  mesh_server_ssl_ctx = mesh_server_ssl_ctx,

  certificate = certificate,
  rewrite = rewrite,
}
