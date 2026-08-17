local pl_utils = require "pl.utils"
local pl_path = require "pl.path"


local _M = {}


do
  local _system_infos


  function _M.get_system_infos()
    if _system_infos then
      return _system_infos
    end

    _system_infos = {}

    local ok, _, stdout = pl_utils.executeex("getconf _NPROCESSORS_ONLN")
    if ok then
      _system_infos.cores = tonumber(stdout:sub(1, -2))
    end

    ok, _, stdout = pl_utils.executeex("uname -ms")
    if ok then
      _system_infos.uname = stdout:gsub(";", ","):sub(1, -2)
    end

    return _system_infos
  end
end


do
  local trusted_certs_paths = {
    "/etc/ssl/certs/ca-certificates.crt",                -- Debian/Ubuntu/Gentoo
    "/etc/pki/tls/certs/ca-bundle.crt",                  -- Fedora/RHEL 6
    "/etc/ssl/ca-bundle.pem",                            -- OpenSUSE
    "/etc/pki/tls/cacert.pem",                           -- OpenELEC
    "/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem", -- CentOS/RHEL 7
    "/etc/ssl/cert.pem",                                 -- OpenBSD, Alpine
  }


  function _M.get_system_trusted_certs_filepath()
    for _, path in ipairs(trusted_certs_paths) do
      if pl_path.exists(path) then
        return path
      end
    end

    return nil,
           "Could not find trusted certs file in " ..
           "any of the `system`-predefined locations. " ..
           "Please install a certs file there or set " ..
           "`lua_ssl_trusted_certificate` to a " ..
           "specific file path instead of `system`"
  end
end


return _M
