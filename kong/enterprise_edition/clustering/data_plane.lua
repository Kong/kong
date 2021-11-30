-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local jwe = require "kong.enterprise_edition.jwe"


local ENCRYPTION_OPTIONS = { zip = "DEF" }


local function encrypt_config(pub, plaintext)
  local alg, err = jwe.key2alg(pub)
  if not alg then
    return nil, err
  end

  return jwe.encrypt(alg, "A256GCM", pub, plaintext, ENCRYPTION_OPTIONS)
end


local function decrypt_config(pub, pri, ciphertext)
  local alg, err = jwe.key2alg(pub)
  if not alg then
    return nil, err
  end

  return jwe.decrypt(alg, "A256GCM", pri, ciphertext)
end


local _M = {}


function _M:encode_config(config)
  return encrypt_config(self.cert_public, config)
end


function _M:decode_config(config)
  return decrypt_config(self.cert_public, self.cert_private, config)
end


return _M
