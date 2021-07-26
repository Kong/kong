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