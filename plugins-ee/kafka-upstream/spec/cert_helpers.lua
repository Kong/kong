-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

-- Note: The certificate/key paths are only available in the pongo context.

-- Load certificate
local f = assert(io.open("/kong-plugin/.pongo/kafka/keystore/certchain.crt"))
local cert_data = f:read("*a")
f:close()

-- Load private key
local f = assert(io.open("/kong-plugin/.pongo/kafka/keystore/privkey.key"))
local key_data = f:read("*a")
f:close()

return {
  cert = cert_data,
  key = key_data
}