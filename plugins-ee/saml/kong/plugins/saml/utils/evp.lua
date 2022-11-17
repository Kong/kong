-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local _M = {}

local RSASigner = {}
RSASigner.__index = RSASigner
_M.RSASigner = RSASigner

--- Create a new RSASigner
-- @param pem_private_key A private key string in PEM format
-- @returns RSASigner, err_string
function RSASigner:new(pem_private_key)
    assert(self == RSASigner, "method 'new' can only be called as 'RSASigner:new(pem_private_key)'")
    self = setmetatable({}, RSASigner)
    local evp_pkey = require("resty.openssl.pkey").new(pem_private_key)
    self.evp_pkey = evp_pkey
    return self, nil
end

--- Sign a message
-- @param message The message to sign
-- @param digest_name The digest format to use (e.g., "SHA256")
-- @returns signature, error_string
function RSASigner:sign(message, digest_name)
    local digest = require("resty.openssl.digest").new(digest_name)
    digest:update(message)
    return self.evp_pkey:sign(digest)
end

local RSAVerifier = {}
RSAVerifier.__index = RSAVerifier
_M.RSAVerifier = RSAVerifier

--- Create a new RSAVerifier
-- @param cert An instance of Cert used for verification
-- @returns RSAVerifier, error_string
function RSAVerifier:new(cert)
    assert(self == RSAVerifier, "method 'new' can only be called as 'RSAVerifier:new(cert)'")
    self = setmetatable({}, RSAVerifier)
    if not cert then
        return nil, "You must pass in a Cert for a public key"
    end
    local evp_public_key, err = cert:get_public_key()
    if not evp_public_key then
        return nil, err
    end

    self.evp_pkey = evp_public_key
    return self
end

--- Verify a message is properly signed
-- @param message The original message
-- @param the signature to verify
-- @param digest_name The digest type that was used to sign
-- @returns bool, error_string
function RSAVerifier:verify(message, sig, digest_name)
    local digest = require("resty.openssl.digest").new(digest_name)
    digest:update(message)
    local ok, err = self.evp_pkey:verify(sig, digest)
    if ok then
      return true
    else
      return nil, err and ("Verification failed: " .. tostring(err)) or "Verification failed"
    end
end

local Cert = {}
Cert.__index = Cert
_M.Cert = Cert

local x509 = require "resty.openssl.x509"

--- Create a new Certificate object
-- @param payload A PEM or DER format X509 certificate
-- @returns Cert, error_string
function Cert:new(payload)
    assert(self == Cert, "method 'new' can only be called as 'Cert:new(payload)'")
    self = setmetatable({}, Cert)
    if not payload then
        return nil, "Must pass a PEM or binary DER cert"
    end

    local x509, err = x509.new(payload, "*")
    if not x509 then
      return nil, err
    end

    self.x509 = x509
    return self
end

--- Retrieve the public key from the CERT
-- @returns An OpenSSL EVP PKEY object representing the public key
function Cert:get_public_key()
  return self.x509:get_pubkey()

end

return _M
