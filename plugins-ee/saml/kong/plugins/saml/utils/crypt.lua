-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local cipher = require "resty.openssl.cipher"
local rand   = require "resty.openssl.rand"

local utils   = require "kong.tools.utils"


local CIPHER  = "aes256"
local IV_SIZE = 16


local function generate_key()
  return string.sub(ngx.encode_base64(utils.get_rand_bytes(32, true)), 1, 32)
end


local function encrypt(s, key)
  assert(s)
  assert(key)
  local encrypter = cipher.new(CIPHER)
  local iv = assert(rand.bytes(IV_SIZE))
  local encrypted = assert(encrypter:encrypt(key, iv, s))
  return ngx.encode_base64(iv .. encrypted)
end


local function decrypt(encoded, key)
  assert(encoded)
  assert(key)
  local s = assert(ngx.decode_base64(encoded))
  local decrypter = assert(cipher.new(CIPHER))
  local iv = string.sub(s, 1, IV_SIZE)
  return assert(decrypter:decrypt(key, iv, string.sub(s, IV_SIZE + 1)))
end


return {
  encrypt = encrypt,
  decrypt = decrypt,
  generate_key = generate_key,
}
