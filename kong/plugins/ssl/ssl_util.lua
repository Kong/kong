local IO = require "kong.tools.io"

local _M = {}

local function execute_openssl(data, cmd)
  local result
  -- Create temp files
  local input = os.tmpname()
  local output = os.tmpname()
  
  -- Populate input file
  IO.write_to_file(input, data)

  -- Execute OpenSSL command
  local res, code = IO.os_execute(string.format(cmd, input, output))
  if code == 0 then
    result = IO.read_file(output)
  end

  -- Remove temp files
  os.remove(input)
  os.remove(output)

  return result
end

function _M.cert_to_der(data)
  return execute_openssl(data, "openssl x509 -outform der -in %s -out %s")
end

function _M.key_to_der(data)
  return execute_openssl(data, "openssl rsa -in %s -inform PEM -out %s -outform DER")
end

return _M