local openssl_bignum = require "openssl.bignum"
local openssl_pkey = require "openssl.pkey"
local openssl_rand = require "openssl.rand"
local x509 = require "openssl.x509"
local x509_extension = require "openssl.x509.extension"
local x509_name = require "openssl.x509.name"
local generate_uuid = require "kong.tools.utils".uuid


-- Create a new private key (for either CA or node)
local function new_key()
  local key = openssl_pkey.new { bits = 2048 }
  return key
end


-- Create CA
local function new_ca(key)
  -- build cert
  local crt = x509.new()
  crt:setPublicKey(key)
  crt:setVersion(3)
  crt:setSerial(openssl_bignum.fromBinary(openssl_rand.bytes(16)))
  -- last for 20 years
  local now = os.time()
  crt:setLifetime(now, now+86400*365*20)
  -- who are we?
  local dn = x509_name.new()
  dn:add("CN", "kong-cluster-" .. generate_uuid())
  crt:setSubject(dn)
  -- should match subject for a self-signed
  crt:setIssuer(dn)
  -- Set up as CA
  crt:setBasicConstraints { CA = true }
  crt:setBasicConstraintsCritical(true)
  crt:addExtension(x509_extension.new("keyUsage", "critical,keyCertSign,cRLSign"))
  -- RFC-3280 4.2.1.2
  crt:addExtension(x509_extension.new("subjectKeyIdentifier", "hash", { subject = crt }))
  crt:addExtension(x509_extension.new("authorityKeyIdentifier", "keyid", { issuer = crt }))
  -- All done; sign
  crt:sign(key)
  return crt
end


local function new_node_cert(ca_key, ca_crt, req)
  local node_id = req.node_id
  local node_pub_key = req.node_pub_key
  -- build desired cert
  local crt = x509.new()
  crt:setPublicKey(node_pub_key)
  crt:setVersion(3)
  crt:setSerial(openssl_bignum.fromBinary(openssl_rand.bytes(16)))
  -- last for 20 years
  local now = os.time()
  crt:setLifetime(now, now+86400*365*20)
  -- who are we?
  crt:setSubject(x509_name.new():add("CN", "kong-node-" .. node_id))
  crt:setIssuer(ca_crt:getSubject())
  -- Not a CA
  crt:setBasicConstraints { CA = false }
  crt:setBasicConstraintsCritical(true)
  -- Only allowed to be used for TLS connections (client or server)
  crt:addExtension(x509_extension.new("extendedKeyUsage", "serverAuth,clientAuth"))
  -- RFC-3280 4.2.1.2
  crt:addExtension(x509_extension.new("subjectKeyIdentifier", "hash", { subject = crt }))
  crt:addExtension(x509_extension.new("authorityKeyIdentifier", "keyid", { issuer = ca_crt }))
  -- All done; sign
  crt:sign(ca_key)
  return crt
end


return {
  new_key = new_key,
  new_ca = new_ca,
  new_node_cert = new_node_cert,
}
