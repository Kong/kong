-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

---
-- JWE utility module
--
-- Provides utility functions around JSON Web Encryption.
--
-- @module kong.jwe

local jwe = require "kong.enterprise_edition.jwe"

local function new(self)
  local _JWE = {}

--- Decrypt JWE encrypted JWT token and returns its payload as plaintext
-- Supported keys (`key` argument):
-- * Supported key formats:
--   * `JWK` (given as a `string` or `table`)
--   * `PEM` (given as a `string`)
--   * `DER` (given as a `string`)
-- * Supported key types:
--   * `RSA`
--   * `EC`, supported curves:
--     * `P-256`
--     * `P-384`
--     * `P-521`
--
-- @usage
-- local jwe = require "kong.enterprise_edition.jwe"
-- local jwk = {
--   kty = "EC",
--   crv = "P-256",
--   use = "enc",
--   x   = "MKBCTNIcKUSDii11ySs3526iDZ8AiTo7Tu6KPAqv7D4",
--   y   = "4Etl6SRW2YiLUrN5vfvVHuhp7x8PxltmWWlbbM4IFyM",
--   d   = "870MB6gfuTJ4HtUnUvYMyJpr5eUZNP4Bk43bVdj3eAE",
-- }
-- local plaintext, err = jwe.decrypt(jwk,
--   "eyJhbGciOiJFQ0RILUVTIiwiZW5jIjoiQTI1NkdDTSIsImFwdSI6Ik1lUFhUS2oyWFR1NUktYldUSFI2bXci" ..
--   "LCJhcHYiOiJmUHFoa2hfNkdjVFd1SG5YWFZBclVnIiwiZXBrIjp7Imt0eSI6IkVDIiwiY3J2IjoiUC0yNTYi" ..
--   "LCJ4IjoiWWd3eF9NVXRLTW9NYUpNZXFhSjZjUFV1Z29oYkVVc0I1NndrRlpYRjVMNCIsInkiOiIxaEYzYzlR" ..
--   "VEhELVozam1vYUp2THZwTGJqcVNaSW9KNmd4X2YtUzAtZ21RIn19..4ZrIopIhLi3LeXyE.-Ke4ofA.MI5lT" ..
--   "kML5NIa-Twm-92F6Q")
-- if plaintext then
--   print(plaintext) -- outputs "hello"
-- end
--
-- @function kong.enterprise_edition.jwe.decrypt
--
-- @tparam   string|table  key    Private key
-- @tparam   string        token  JWE encrypted JWT token
-- @treturn  string               JWT token payload in plaintext, or nil
-- @treturn  string               Error message, or nil
  function _JWE:decrypt(key, jwe_token)
    return jwe.decrypt(key, jwe_token)
  end


--- Decode JWE encrypted JWT token and return a table containing its parts
--
-- This function will return a table that looks like this:
-- ```
-- {
--   [1] = protected header (as it appears in token)
--   [2] = encrypted key (as it appears in token)
--   [3] = initialization vector (as it appears in token)
--   [4] = ciphertext (as it appears in token)
--   [5] = authentication tag (as it appears in token)
--   protected = protected key (base64url decoded and json decoded)
--   encrypted_key = encrypted key (base64url decoded)
--   iv = initialization vector (base64url decoded)
--   ciphertext = ciphertext (base64url decoded)
--   tag = authentication tag (base64url decoded)
--   aad = protected header (as it appears in token)
-- }
-- ```
--
-- The original input can be reconstructed with:
-- ```
-- local token = table.concat(<decoded-table>, ".")
-- ```
--
-- If there is not exactly 5 parts in JWT token, or any decoding fails,
-- the error is returned.
--
-- @usage
-- local jwe = require "kong.enterprise_edition.jwe"
-- local jwt, err = jwe.decode(
--   "eyJhbGciOiJFQ0RILUVTIiwiZW5jIjoiQTI1NkdDTSIsImFwdSI6Ik1lUFhUS2oyWFR1NUktYldUSFI2bXci" ..
--   "LCJhcHYiOiJmUHFoa2hfNkdjVFd1SG5YWFZBclVnIiwiZXBrIjp7Imt0eSI6IkVDIiwiY3J2IjoiUC0yNTYi" ..
--   "LCJ4IjoiWWd3eF9NVXRLTW9NYUpNZXFhSjZjUFV1Z29oYkVVc0I1NndrRlpYRjVMNCIsInkiOiIxaEYzYzlR" ..
--   "VEhELVozam1vYUp2THZwTGJqcVNaSW9KNmd4X2YtUzAtZ21RIn19..4ZrIopIhLi3LeXyE.-Ke4ofA.MI5lT" ..
--   "kML5NIa-Twm-92F6Q")
-- if jwt then
--   print(jwt.protected.alg) -- outputs "ECDH-ES"
-- end
--
-- @function kong.enterprise_edition.jwe.decode
--
-- @tparam   string  token  JWE encrypted JWT token
-- @treturn  string         A table containing JWT token parts decoded, or nil
-- @treturn  string         Error message, or nil
  function _JWE:decode(jwt)
    local token_table, err = jwe.decode(jwt)
    if err then
      return nil, err
    end
    return token_table, nil
  end


--- Encrypt plaintext using JWE encryption and returns a JWT token
--
-- Supported algorithms (`alg` argument):
-- * `"RSA-OAEP"`
-- * `"ECDH-ES"`
--
-- Supported encryption algorithms (`enc` argument):
-- * `"A256GCM"`
--
-- Supported keys (`key` argument):
-- * Supported key formats:
--   * `JWK` (given as a `string` or `table`)
--   * `PEM` (given as a `string`)
--   * `DER` (given as a `string`)
-- * Supported key types:
--   * `RSA`
--   * `EC`, supported curves:
--     * `P-256`
--     * `P-384`
--     * `P-521`
--
-- Supported options (`options` argument):
-- * `{ zip = "DEF" }`: whether to deflate the plaintext before encrypting
-- * `{ apu = <string|boolean> }`: Agreement PartyUInfo header parameter
-- * `{ apv = <string|boolean> }`: Agreement PartyVInfo header parameter
--
-- The `apu` and `apv` can also be set to `false` to prevent them from
-- being auto-generated (sixteen random bytes) and added to ephemeral
-- public key.
--
-- @usage
-- local jwe = require "kong.enterprise_edition.jwe"
-- local jwk = {
--   kty = "EC",
--   crv = "P-256",
--   use = "enc",
--   x   = "MKBCTNIcKUSDii11ySs3526iDZ8AiTo7Tu6KPAqv7D4",
--   y   = "4Etl6SRW2YiLUrN5vfvVHuhp7x8PxltmWWlbbM4IFyM",
-- }
-- local token, err = jwe.encrypt("ECDH-ES", "A256GCM", jwk, "hello", {
--   zip = "DEF,
-- })
-- if token then
--   print(token)
-- end
--
-- @function kong.enterprise_edition.jwe.encrypt
--
-- @tparam        string        alg        Algorithm used for key management
-- @tparam        string        enc        Encryption algorithm used for content encryption
-- @tparam        string|table  key        Public key
-- @tparam        string        plaintext  Plaintext
-- @tparam[opt]   table         options    Options (optional), default: nil
-- @treturn       string                   JWE encrypted JWT token, or nil
-- @treturn       string                   Error message, or nil
  function _JWE:encrypt(alg, enc, key, plaintext, options)
    return jwe.encrypt(alg, enc, key, plaintext, options)
  end

  return _JWE
end

return {
  new = new,
}
