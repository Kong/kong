local openssl_pkey = require "openssl.pkey"
local openssl_x509 = require "openssl.x509"
local singletons = require "kong.singletons"
local ca = require "kong.tools.ca"
local public = require "kong.tools.public"

local encode_base64 = ngx.encode_base64

local mesh_alpn
local function init()
  -- This should run in init phase (in master, not worker)
  local ca_crt, node_private_key, node_cert do
    -- We need to get the CA certificate to be able to verify peers
    -- We want to generate ourselves a node certificate

    -- Try and get CA key + cert from DB
    local ca_row, err = singletons.db.ca:select({ pk = true })
    if not ca_row and err == nil then
      -- No CA cert in DB, we are the first cluster member to start

      -- Generate a CA
      local candidate_ca_key = ca.new_key()
      local candidate_ca_cert = ca.new_ca(candidate_ca_key)

      -- Try and add it to DB, if there is a conflict, some other node beat us to it
      ca_row = {
        pk = true,
        key = candidate_ca_key:toPEM("private"),
        cert = candidate_ca_cert:toPEM(),
      }
      local ok
      ok, err = singletons.db.ca:insert(ca_row)
      if not ok then
        ca_row = nil
        if err:match("conflict") then
          -- Another node starting up beat us, redo the query.
          ca_row, err = singletons.db.ca:select({ pk = true })
        end
      end
    end
    if not ca_row then
      error(err)
    end

    local ca_key = openssl_pkey.new(ca_row.key)
    ca_crt = openssl_x509.new(ca_row.cert)

    -- Generate our node cert
    node_private_key = ca.new_key()
    local node_public_key = openssl_pkey.new(node_private_key:toPEM("public"))

    node_cert = ca.new_node_cert(ca_key, ca_crt, {
      node_id = assert(public.get_node_id()),
      node_pub_key = node_public_key,
    })
  end -- ca_key should never leave this scope

  -- Create a unique id for *this* service mesh
  -- - Should be < 256 bytes
  -- - Should be ascii-safe
  -- - Self-identifies as Kong
  -- - Versioned in case scheme is changed later
  local cluster_id = encode_base64(ca_crt:getPublicKeyDigest("sha256"))
  mesh_alpn = "com.konghq/service-mesh/1/" .. cluster_id

  ngx.log(ngx.DEBUG, "mesh initialised, cluster alpn is ", mesh_alpn)
  ngx.log(ngx.DEBUG, "node certificate generated. fingerprint is ",
                     encode_base64(node_cert:getPublicKeyDigest("sha256")))
end


local function get_mesh_alpn()
  assert(mesh_alpn ~= nil, "mesh is not initialised: missing call to runloop.mesh.init()")
  return mesh_alpn
end


return {
  init = init,
  get_mesh_alpn = get_mesh_alpn,
}
