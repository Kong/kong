local cutils = require "kong.cli.utils"
local utils = require "kong.tools.utils"
local IO = require "kong.tools.io"

local _M = {}

function _M.get_ssl_cert_and_key(kong_config)
  local ssl_cert_path, ssl_key_path

  if (kong_config.ssl_cert_path and not kong_config.ssl_key_path) or
    (kong_config.ssl_key_path and not kong_config.ssl_cert_path) then
    cutils.logger:error_exit("Both \"ssl_cert_path\" and \"ssl_key_path\" need to be specified in the configuration, or none of them")
  elseif kong_config.ssl_cert_path and kong_config.ssl_key_path then
    ssl_cert_path = kong_config.ssl_cert_path
    ssl_key_path = kong_config.ssl_key_path
  else
    ssl_cert_path = IO.path:join(cutils.get_luarocks_install_dir(), "ssl", "kong-default.crt")
    ssl_key_path = IO.path:join(cutils.get_luarocks_install_dir(), "ssl", "kong-default.key")
  end

  -- Check that the file exists
  if ssl_cert_path and not IO.file_exists(ssl_cert_path) then
    cutils.logger:error_exit("Can't find default Kong SSL certificate at: "..ssl_cert_path)
  end
  if ssl_key_path and not IO.file_exists(ssl_key_path) then
    cutils.logger:error_exit("Can't find default Kong SSL key at: "..ssl_key_path)
  end

  return ssl_cert_path, ssl_key_path
end

function _M.prepare_ssl()
  local ssl_cert_path = IO.path:join(cutils.get_luarocks_install_dir(), "ssl", "kong-default.crt")
  local ssl_key_path = IO.path:join(cutils.get_luarocks_install_dir(), "ssl", "kong-default.key")

  if not (IO.file_exists(ssl_cert_path) and IO.file_exists(ssl_key_path)) then
    -- Autogenerating the certificates for the first time
    cutils.logger:info("Auto-generating the default SSL certificate and key...")

    local file_name = os.tmpname()
    local passphrase = utils.random_string()

    IO.os_execute([[
      cd /tmp && \
      openssl genrsa -des3 -out ]]..file_name..[[.key -passout pass:]]..passphrase..[[ 1024 && \
      openssl req -new -key ]]..file_name..[[.key -out ]]..file_name..[[.csr -subj "/C=US/ST=California/L=San Francisco/O=Kong/OU=IT Department/CN=localhost" -passin pass:]]..passphrase..[[ && \
      cp ]]..file_name..[[.key ]]..file_name..[[.key.org && \
      openssl rsa -in ]]..file_name..[[.key.org -out ]]..file_name..[[.key -passin pass:]]..passphrase..[[ && \
      openssl x509 -req -in ]]..file_name..[[.csr -signkey ]]..file_name..[[.key -out ]]..file_name..[[.crt && \
      sudo mv ]]..file_name..[[.crt ]]..ssl_cert_path..[[ && \
      sudo mv ]]..file_name..[[.key ]]..ssl_key_path)
  end
end

return _M