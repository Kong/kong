-- Copyright (C) 2014 Yichun Zhang


local ffi = require "ffi"
local base = require "resty.core.base"


local C = ffi.C
local ffi_str = ffi.string
local getfenv = getfenv
local errmsg = base.get_errmsg_ptr()
local get_string_buf = base.get_string_buf
local get_string_buf_size = base.get_string_buf_size
local get_size_ptr = base.get_size_ptr
local FFI_DECLINED = base.FFI_DECLINED
local FFI_OK = base.FFI_OK
local FFI_BUSY = base.FFI_BUSY
local FFI_DECLINED = base.FFI_DECLINED


ffi.cdef[[

struct ngx_ssl_conn_s;
typedef struct ngx_ssl_conn_s  ngx_ssl_conn_t;

int ngx_http_lua_ffi_ssl_set_der_certificate(ngx_http_request_t *r,
    const char *data, size_t len, char **err);

int ngx_http_lua_ffi_ssl_clear_certs(ngx_http_request_t *r, char **err);

int ngx_http_lua_ffi_ssl_set_der_private_key(ngx_http_request_t *r,
    const char *data, size_t len, char **err);

int ngx_http_lua_ffi_ssl_raw_server_addr(ngx_http_request_t *r, char **addr,
    size_t *addrlen, int *addrtype, char **err);

int ngx_http_lua_ffi_ssl_server_name(ngx_http_request_t *r, char **name,
    size_t *namelen, char **err);

int ngx_http_lua_ffi_cert_pem_to_der(const unsigned char *pem, size_t pem_len,
    unsigned char *der, char **err);

int ngx_http_lua_ffi_ssl_get_ocsp_responder_from_der_chain(
    const char *chain_data, size_t chain_len, char *out, size_t *out_size,
    char **err);

int ngx_http_lua_ffi_ssl_create_ocsp_request(const char *chain_data,
    size_t chain_len, unsigned char *out, size_t *out_size, char **err);

int ngx_http_lua_ffi_ssl_validate_ocsp_response(const unsigned char *resp,
    size_t resp_len, const char *chain_data, size_t chain_len,
    unsigned char *errbuf, size_t *errbuf_size);

int ngx_http_lua_ffi_ssl_set_ocsp_status_resp(ngx_http_request_t *r,
    const unsigned char *resp, size_t resp_len, char **err);

int ngx_http_lua_ffi_ssl_get_tls1_version(ngx_http_request_t *r, char **err);
]]


local _M = {}


local charpp = ffi.new("char*[1]")
local intp = ffi.new("int[1]")


function _M.clear_certs(data)
    local r = getfenv(0).__ngx_req
    if not r then
        return error("no request found")
    end

    local rc = C.ngx_http_lua_ffi_ssl_clear_certs(r, errmsg)
    if rc == FFI_OK then
        return true
    end

    return nil, ffi_str(errmsg[0])
end


function _M.set_der_cert(data)
    local r = getfenv(0).__ngx_req
    if not r then
        return error("no request found")
    end

    local rc = C.ngx_http_lua_ffi_ssl_set_der_certificate(r, data, #data,
                                                          errmsg)
    if rc == FFI_OK then
        return true
    end

    return nil, ffi_str(errmsg[0])
end


function _M.set_der_priv_key(data)
    local r = getfenv(0).__ngx_req
    if not r then
        return error("no request found")
    end

    local rc = C.ngx_http_lua_ffi_ssl_set_der_private_key(r, data, #data,
                                                          errmsg)
    if rc == FFI_OK then
        return true
    end

    return nil, ffi_str(errmsg[0])
end


local addr_types = {
    [1] = "unix",
    [2] = "inet",
    [10] = "inet6",
}


function _M.raw_server_addr()
    local r = getfenv(0).__ngx_req
    if not r then
        return error("no request found")
    end

    local sizep = get_size_ptr()

    local rc = C.ngx_http_lua_ffi_ssl_raw_server_addr(r, charpp, sizep,
                                                      intp, errmsg)
    if rc == FFI_OK then
        local typ = addr_types[intp[0]]
        if not typ then
            return nil, nil, "unknown address type: " .. intp[0]
        end
        return ffi_str(charpp[0], sizep[0]), typ
    end

    return nil, nil, ffi_str(errmsg[0])
end


function _M.server_name()
    local r = getfenv(0).__ngx_req
    if not r then
        return error("no request found")
    end

    local sizep = get_size_ptr()

    local rc = C.ngx_http_lua_ffi_ssl_server_name(r, charpp, sizep, errmsg)
    if rc == FFI_OK then
        return ffi_str(charpp[0], sizep[0])
    end

    if rc == FFI_DECLINED then
        return nil
    end

    return nil, ffi_str(errmsg[0])
end


function _M.cert_pem_to_der(pem)
    local r = getfenv(0).__ngx_req
    if not r then
        return error("no request found")
    end

    local outbuf = get_string_buf(#pem)

    local sz = C.ngx_http_lua_ffi_cert_pem_to_der(pem, #pem, outbuf, errmsg)
    if sz > 0 then
        return ffi_str(outbuf, sz)
    end

    return nil, ffi_str(errmsg[0])
end


function _M.get_ocsp_responder_from_der_chain(data, maxlen)

    local buf_size = maxlen
    if not buf_size then
        buf_size = get_string_buf_size()
    end
    local buf = get_string_buf(buf_size)

    local sizep = get_size_ptr()
    sizep[0] = buf_size

    local rc = C.ngx_http_lua_ffi_ssl_get_ocsp_responder_from_der_chain(data,
                                                    #data, buf, sizep, errmsg)

    if rc == FFI_DECLINED then
        return nil
    end

    if rc == FFI_OK then
        return ffi_str(buf, sizep[0])
    end

    if rc == FFI_BUSY then
        return ffi_str(buf, sizep[0]), "truncated"
    end

    return nil, ffi_str(errmsg[0])
end


function _M.create_ocsp_request(data, maxlen)

    local buf_size = maxlen
    if not buf_size then
        buf_size = get_string_buf_size()
    end
    local buf = get_string_buf(buf_size)

    local sizep = get_size_ptr()
    sizep[0] = buf_size

    local rc = C.ngx_http_lua_ffi_ssl_create_ocsp_request(data,
                                                          #data, buf, sizep,
                                                          errmsg)

    if rc == FFI_OK then
        return ffi_str(buf, sizep[0])
    end

    if rc == FFI_BUSY then
        return nil, ffi_str(errmsg[0]) .. ": " .. tonumber(sizep[0])
               .. " > " .. buf_size
    end

    return nil, ffi_str(errmsg[0])
end


function _M.validate_ocsp_response(resp, chain, max_errmsg_len)

    local errbuf_size = max_errmsg_len
    if not errbuf_size then
        errbuf_size = get_string_buf_size()
    end
    local errbuf = get_string_buf(errbuf_size)

    local sizep = get_size_ptr()
    sizep[0] = errbuf_size

    local rc = C.ngx_http_lua_ffi_ssl_validate_ocsp_response(
                        resp, #resp, chain, #chain, errbuf, sizep)

    if rc == FFI_OK then
        return true
    end

    -- rc == FFI_ERROR

    return nil, ffi_str(errbuf, sizep[0])
end


function _M.set_ocsp_status_resp(data)
    local r = getfenv(0).__ngx_req
    if not r then
        return error("no request found")
    end

    local rc = C.ngx_http_lua_ffi_ssl_set_ocsp_status_resp(r, data, #data,
                                                           errmsg)

    if rc == FFI_DECLINED then
        -- no client status req
        return true, "no status req"
    end

    if rc == FFI_OK then
        return true
    end

    -- rc == FFI_ERROR

    return nil, ffi_str(errmsg[0])
end


local function get_tls1_version()

    local r = getfenv(0).__ngx_req
    if not r then
        return error("no request found")
    end

    local ver = C.ngx_http_lua_ffi_ssl_get_tls1_version(r, errmsg)

    ver = tonumber(ver)

    if ver >= 0 then
        return ver
    end

    -- rc == FFI_ERROR

    return nil, ffi_str(errmsg[0])
end
_M.get_tls1_version = get_tls1_version


do
    _M.SSL3_VERSION = 0x0300
    _M.TLS1_VERSION = 0x0301
    _M.TLS1_1_VERSION = 0x0302
    _M.TLS1_2_VERSION = 0x0303

    local map = {
        [_M.SSL3_VERSION] = "SSLv3",
        [_M.TLS1_VERSION] = "TLSv1",
        [_M.TLS1_1_VERSION] = "TLSv1.1",
        [_M.TLS1_2_VERSION] = "TLSv1.2",
    }

    function _M.get_tls1_version_str()
        local ver, err = get_tls1_version()
        if not ver then
            return nil, err
        end
        return map[ver]
    end
end


return _M
