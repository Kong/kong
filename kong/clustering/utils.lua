

local constants = require("kong.constants")
local openssl_x509 = require("resty.openssl.x509")
local ssl = require("ngx.ssl")
local ocsp = require("ngx.ocsp")
local http = require("resty.http")
local system_constants = require("lua_system_constants")
local bit = require("bit")
local ffi = require("ffi")

local io_open = io.open
local ngx_var = ngx.var
local cjson_decode = require "cjson.safe".decode
local cjson_encode = require "cjson.safe".encode

local ngx_log = ngx.log
local ngx_ERR = ngx.ERR
local ngx_INFO = ngx.INFO
local ngx_WARN = ngx.WARN
local _log_prefix = "[clustering] "

local CONFIG_CACHE = ngx.config.prefix() .. "/config.cache.json.gz"

local MAJOR_MINOR_PATTERN = "^(%d+)%.(%d+)%.%d+"
local CLUSTERING_SYNC_STATUS = constants.CLUSTERING_SYNC_STATUS
local OCSP_TIMEOUT = constants.CLUSTERING_OCSP_TIMEOUT



local clustering_utils = {}


function clustering_utils.extract_major_minor(version)
  if type(version) ~= "string" then
    return nil, nil
  end

  local major, minor = version:match(MAJOR_MINOR_PATTERN)
  if not major then
    return nil, nil
  end

  major = tonumber(major, 10)
  minor = tonumber(minor, 10)

  return major, minor
end

function clustering_utils.check_kong_version_compatibility(cp_version, dp_version, log_suffix)
  local major_cp, minor_cp = clustering_utils.extract_major_minor(cp_version)
  local major_dp, minor_dp = clustering_utils.extract_major_minor(dp_version)

  if not major_cp then
    return nil, "data plane version " .. dp_version .. " is incompatible with control plane version",
    CLUSTERING_SYNC_STATUS.KONG_VERSION_INCOMPATIBLE
  end

  if not major_dp then
    return nil, "data plane version is incompatible with control plane version " ..
      cp_version .. " (" .. major_cp .. ".x.y are accepted)",
    CLUSTERING_SYNC_STATUS.KONG_VERSION_INCOMPATIBLE
  end

  if major_cp ~= major_dp then
    return nil, "data plane version " .. dp_version ..
      " is incompatible with control plane version " ..
      cp_version .. " (" .. major_cp .. ".x.y are accepted)",
    CLUSTERING_SYNC_STATUS.KONG_VERSION_INCOMPATIBLE
  end

  if minor_cp < minor_dp then
    return nil, "data plane version " .. dp_version ..
      " is incompatible with older control plane version " .. cp_version,
    CLUSTERING_SYNC_STATUS.KONG_VERSION_INCOMPATIBLE
  end

  if minor_cp ~= minor_dp then
    local msg = "data plane minor version " .. dp_version ..
      " is different to control plane minor version " ..
      cp_version

    ngx_log(ngx_INFO, _log_prefix, msg, log_suffix or "")
  end

  return true, nil, CLUSTERING_SYNC_STATUS.NORMAL
end


local function validate_shared_cert(cert_digest)
  local cert = ngx_var.ssl_client_raw_cert

  if not cert then
    return nil, "data plane failed to present client certificate during handshake"
  end

  local err
  cert, err = openssl_x509.new(cert, "PEM")
  if not cert then
    return nil, "unable to load data plane client certificate during handshake: " .. err
  end

  local digest
  digest, err = cert:digest("sha256")
  if not digest then
    return nil, "unable to retrieve data plane client certificate digest during handshake: " .. err
  end

  if digest ~= cert_digest then
    return nil, "data plane presented incorrect client certificate during handshake (expected: " ..
      cert_digest .. ", got: " .. digest .. ")"
  end

  return true
end

local check_for_revocation_status
do
  local get_full_client_certificate_chain = require("resty.kong.tls").get_full_client_certificate_chain
  check_for_revocation_status = function()
    local cert, err = get_full_client_certificate_chain()
    if not cert then
      return nil, err or "no client certificate"
    end

    local der_cert
    der_cert, err = ssl.cert_pem_to_der(cert)
    if not der_cert then
      return nil, "failed to convert certificate chain from PEM to DER: " .. err
    end

    local ocsp_url
    ocsp_url, err = ocsp.get_ocsp_responder_from_der_chain(der_cert)
    if not ocsp_url then
      return nil, err or "OCSP responder endpoint can not be determined, " ..
        "maybe the client certificate is missing the " ..
        "required extensions"
    end

    local ocsp_req
    ocsp_req, err = ocsp.create_ocsp_request(der_cert)
    if not ocsp_req then
      return nil, "failed to create OCSP request: " .. err
    end

    local c = http.new()
    local res
    res, err = c:request_uri(ocsp_url, {
      headers = {
        ["Content-Type"] = "application/ocsp-request"
      },
      timeout = OCSP_TIMEOUT,
      method = "POST",
      body = ocsp_req,
    })

    if not res then
      return nil, "failed sending request to OCSP responder: " .. tostring(err)
    end
    if res.status ~= 200 then
      return nil, "OCSP responder returns bad HTTP status code: " .. res.status
    end

    local ocsp_resp = res.body
    if not ocsp_resp or #ocsp_resp == 0 then
      return nil, "unexpected response from OCSP responder: empty body"
    end

    res, err = ocsp.validate_ocsp_response(ocsp_resp, der_cert)
    if not res then
      return false, "failed to validate OCSP response: " .. err
    end

    return true
  end
end


function clustering_utils.validate_connection_certs(conf, cert_digest)
  local _, err

  -- use mutual TLS authentication
  if conf.cluster_mtls == "shared" then
    _, err = validate_shared_cert(cert_digest)

  elseif conf.cluster_ocsp ~= "off" then
    local ok
    ok, err = check_for_revocation_status()
    if ok == false then
      err = "data plane client certificate was revoked: " ..  err

    elseif not ok then
      if conf.cluster_ocsp == "on" then
        err = "data plane client certificate revocation check failed: " .. err

      else
        ngx_log(ngx_WARN, _log_prefix, "data plane client certificate revocation check failed: ", err)
        err = nil
      end
    end
  end

  if err then
    return nil, err
  end

  return true
end

function clustering_utils.load_config_cache(self)
  local f = io_open(CONFIG_CACHE, "r")
  if f then
    local config, err = f:read("*a")
    if not config then
      ngx_log(ngx_ERR, _log_prefix, "unable to read cached config file: ", err)
    end

    f:close()

    if config and #config > 0 then
      ngx_log(ngx_INFO, _log_prefix, "found cached config, loading...")
      config, err = self:decode_config(config)
      if config then
        config, err = cjson_decode(config)
        if config then
          local res
          res, err = self:update_config(config)
          if not res then
            ngx_log(ngx_ERR, _log_prefix, "unable to update running config from cache: ", err)
          end

        else
          ngx_log(ngx_ERR, _log_prefix, "unable to json decode cached config: ", err, ", ignoring")
        end

      else
        ngx_log(ngx_ERR, _log_prefix, "unable to decode cached config: ", err, ", ignoring")
      end
    end

  else
    -- CONFIG_CACHE does not exist, pre create one with 0600 permission
    local flags = bit.bor(system_constants.O_RDONLY(),
      system_constants.O_CREAT())

    local mode = ffi.new("int", bit.bor(system_constants.S_IRUSR(),
      system_constants.S_IWUSR()))

    local fd = ffi.C.open(CONFIG_CACHE, flags, mode)
    if fd == -1 then
      ngx_log(ngx_ERR, _log_prefix, "unable to pre-create cached config file: ",
        ffi.string(ffi.C.strerror(ffi.errno())))

    else
      ffi.C.close(fd)
    end
  end
end


function clustering_utils.save_config_cache(self, config_table)
  local f, err = io_open(CONFIG_CACHE, "w")
  if not f then
    ngx_log(ngx_ERR, _log_prefix, "unable to open config cache file: ", err)

  else
    local config = assert(cjson_encode(config_table))
    config = assert(self:encode_config(config))
    local res
    res, err = f:write(config)
    if not res then
      ngx_log(ngx_ERR, _log_prefix, "unable to write config cache file: ", err)
    end

    f:close()
  end
end

return clustering_utils
