-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local ffi = require("ffi")
local resty_ja4 = require "resty.ja4"
local lrucache = require "resty.lrucache"

ffi.cdef [[
  extern int SSL_version(const struct ssl_st *s);
  extern int32_t SSL_is_dtls(struct ssl_st *s);
  extern uintptr_t SSL_client_hello_get0_ciphers(struct ssl_st *s, const uint8_t **out);
  extern int32_t SSL_client_hello_get1_extensions_present(struct ssl_st *s,
                              const int32_t **out,
                              size_t *outlen);
  extern int32_t SSL_client_hello_get0_ext(struct ssl_st *s,
                       int32_t typ,
                       const uint8_t **out,
                       size_t *outlen);
  extern void CRYPTO_free(void *str, const char *file, int line);
]]

local DEFAULT_CACHE_MAX_ITEMS = 16384
local DEFAULT_KEEPALIVE_TIMEOUT = 75

local DTLS = ffi.new("uint16_t", 1)
local TCP = ffi.new("uint16_t", 0)

local SignatureAlgorithms = ffi.new("uint16_t", 0x000d)
local ClientProtocolNegotiation = ffi.new("uint16_t", 0x0010)
local SupportedVersions = ffi.new("uint16_t", 0x002b)


local ja4_cache

local _M = {}


local function init_cache()
    local n = tonumber(kong.configuration.nginx_events_worker_connections)
    if not n then
      n = DEFAULT_CACHE_MAX_ITEMS
    end
    ja4_cache = lrucache.new(n)
end


local function get_ja4_cache_timeout()
  local timeout

  if kong and kong.configuration then
    timeout = kong.configuration.nginx_location_keepalive_timeout
              or kong.configuration.nginx_server_keepalive_timeout
              or kong.configuration.nginx_http_keepalive_timeout
  end

  return timeout or DEFAULT_KEEPALIVE_TIMEOUT
end


local function get_extension(ssl_ptr, typ)
  local extension_ffi = ffi.new("const uint8_t*[1]")
  local extension_len_ffi = ffi.new("size_t [1]")
  local exist = ffi.C.SSL_client_hello_get0_ext(ssl_ptr, typ, extension_ffi, extension_len_ffi)
  if exist == 0 then
    return nil, 0
  end
  return extension_ffi[0], extension_len_ffi[0]
end


local function to_u16_array(strip, data, len)
  if data == nil then
    return nil, 0
  end

  if len < strip then
    return nil, 0
  end

  local new_len = (len - strip)/2

  return ffi.cast("uint16_t*", data + strip), new_len
end


function _M.get_fingerprint_from_cache(connection_id)
  if not ja4_cache then
    return nil, "fingerprint not found"
  end

  return ja4_cache:get(connection_id)
end

function _M.set_fingerprint_to_cache(connection_id, fingerprint)
  if not ja4_cache then
    init_cache()
  end

  ja4_cache:set(connection_id, fingerprint, get_ja4_cache_timeout())
end

function _M.compute_ja4_fingerprint(ssl_ptr)
  local protocol = ffi.C.SSL_is_dtls(ssl_ptr) == 1 and DTLS or TCP
  local tls_version = ffi.C.SSL_version(ssl_ptr)
  local supported_version, supported_version_n = to_u16_array(1, get_extension(ssl_ptr, SupportedVersions))

  local ciphers_ffi = ffi.new("const uint8_t*[1]")
  local cipher_n_ffi = ffi.C.SSL_client_hello_get0_ciphers(ssl_ptr, ciphers_ffi)
  local ciphers, cipher_n = to_u16_array(0, ciphers_ffi[0], cipher_n_ffi)

  local extension_list_raw = ffi.new("const int32_t*[1]")
  local extension_n = ffi.new("size_t[1]")
  local result = ffi.C.SSL_client_hello_get1_extensions_present(ssl_ptr, extension_list_raw, extension_n)
  if not result then
    return nil, "failed to get extension IDs"
  end

  local extension_list = ffi.new("uint16_t[?]", extension_n[0])
  for i = 0, tonumber(extension_n[0]) - 1 do
    extension_list[i] = extension_list_raw[0][i]
  end

  local to_free = ffi.cast("void*",extension_list_raw[0])
  -- change the line according when the file is changed
  ffi.C.CRYPTO_free(to_free, "kong/enterprise_edition/tls/ja4/init.lua", 129)

  local alpn, alpn_len = get_extension(ssl_ptr, ClientProtocolNegotiation)
  if alpn and alpn_len > 2 then
    alpn = alpn + 2
    alpn_len = alpn_len - 2
  else
    alpn = nil
    alpn_len = 0
  end

  local sign_algo_extension, sign_algo_len = to_u16_array(2, get_extension(ssl_ptr, SignatureAlgorithms))

  return resty_ja4(protocol,
                   tls_version,
                   supported_version,
                   supported_version_n,
                   ciphers,
                   cipher_n,
                   extension_list,
                   extension_n[0],
                   alpn,
                   alpn_len,
                   sign_algo_extension,
                   sign_algo_len)
end


return _M
