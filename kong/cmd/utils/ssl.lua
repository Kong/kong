local utils = require "kong.tools.utils"
local pl_path = require "pl.path"
local pl_utils = require "pl.utils"
local pl_dir = require "pl.dir"
local log = require "kong.cmd.utils.log"
local fmt = string.format

local _M = {}

local SSL_FOLDER = "ssl"
local SSL_CERT = "kong-default.crt"
local SSL_CERT_KEY = "kong-default.key"
local SSL_CERT_CSR = "kong-default.csr"

function _M.get_ssl_cert_and_key(kong_config, nginx_prefix)
  local ssl_cert, ssl_cert_key
  if kong_config.ssl_cert and kong_config.ssl_cert_key then
    ssl_cert = kong_config.ssl_cert
    ssl_cert_key = kong_config.ssl_cert_key
  else
    ssl_cert = pl_path.join(nginx_prefix, SSL_FOLDER, SSL_CERT)
    ssl_cert_key = pl_path.join(nginx_prefix, SSL_FOLDER, SSL_CERT_KEY)
  end

  -- Check that the files exist
  if not pl_path.exists(ssl_cert) then
    return nil, "cannot find SSL certificate at: "..ssl_cert
  end
  if not pl_path.exists(ssl_cert_key) then
    return nil, "cannot find SSL key at: "..ssl_cert_key
  end

  return { ssl_cert = ssl_cert, ssl_cert_key = ssl_cert_key }
end

function _M.prepare_ssl_cert_and_key(prefix)
  -- Create SSL directory
  local ssl_path = pl_path.join(prefix, SSL_FOLDER)
  local ok, err = pl_dir.makepath(ssl_path)
  if not ok then return nil, err end

  local ssl_cert = pl_path.join(prefix, SSL_FOLDER, SSL_CERT)
  local ssl_cert_key = pl_path.join(prefix, SSL_FOLDER, SSL_CERT_KEY)
  local ssl_cert_csr = pl_path.join(prefix, SSL_FOLDER, SSL_CERT_CSR)

  if not (pl_path.exists(ssl_cert) and pl_path.exists(ssl_cert_key)) then
    -- Autogenerating the certificates for the first time
    log.verbose("Auto-generating the default SSL certificate and key..")

    local passphrase = utils.random_string()
    local commands = {
      fmt("openssl genrsa -des3 -out %s -passout pass:%s 1024", ssl_cert_key, passphrase),
      fmt("openssl req -new -key %s -out %s -subj \"/C=US/ST=California/L=San Francisco/O=Kong/OU=IT Department/CN=localhost\" -passin pass:%s", ssl_cert_key, ssl_cert_csr, passphrase),
      fmt("cp %s %s.org", ssl_cert_key, ssl_cert_key),
      fmt("openssl rsa -in %s.org -out %s -passin pass:%s", ssl_cert_key, ssl_cert_key, passphrase),
      fmt("openssl x509 -req -in %s -signkey %s -out %s", ssl_cert_csr, ssl_cert_key, ssl_cert),
      fmt("rm %s", ssl_cert_csr),
      fmt("rm %s.org", ssl_cert_key)
    }
    for _, cmd in ipairs(commands) do
      local ok, _, _, stderr = pl_utils.executeex(cmd)
      if not ok then
        return nil, "there was an error when auto-generating the default SSL certificate: "..stderr
      end
    end
  end

  return true
end

return _M