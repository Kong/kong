-- Copyright (c) 2015 Adobe Systems Incorporated. All rights reserved.
--
--   Permission is hereby granted, free of charge, to any person obtaining a
--   copy of this software and associated documentation files (the "Software"),
--   to deal in the Software without restriction, including without limitation
--   the rights to use, copy, modify, merge, publish, distribute, sublicense,
--   and/or sell copies of the Software, and to permit persons to whom the
--   Software is furnished to do so, subject to the following conditions:
--
--   The above copyright notice and this permission notice shall be included in
--   all copies or substantial portions of the Software.
--
--   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
--   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
--   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
--   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
--   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
--   FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
--   DEALINGS IN THE SOFTWARE.


-- Adds HMAC support to Lua with multiple algorithms, via OpenSSL and FFI
--
-- Author: ddragosd@gmail.com
-- Date: 16/05/14
--


local ffi = require "ffi"
local ffi_new = ffi.new
local ffi_str = ffi.string
local C = ffi.C
local resty_string = require "resty.string"
local setmetatable = setmetatable
local error = error


local _M = { _VERSION = '0.09' }


local mt = { __index = _M }

--
-- EVP_MD is defined in openssl/evp.h
-- HMAC is defined in openssl/hmac.h
--
ffi.cdef[[
typedef struct env_md_st EVP_MD;
typedef struct env_md_ctx_st EVP_MD_CTX;
unsigned char *HMAC(const EVP_MD *evp_md, const void *key, int key_len,
		    const unsigned char *d, size_t n, unsigned char *md,
		    unsigned int *md_len);
const EVP_MD *EVP_sha1(void);
const EVP_MD *EVP_sha224(void);
const EVP_MD *EVP_sha256(void);
const EVP_MD *EVP_sha384(void);
const EVP_MD *EVP_sha512(void);
]]

-- table definind the available algorithms and the length of each digest
-- for more information @see: http://csrc.nist.gov/publications/fips/fips180-4/fips-180-4.pdf
local available_algorithms = {
    sha1   = { alg = C.EVP_sha1(),   length = 160/8  },
    sha224 = { alg = C.EVP_sha224(), length = 224/8  },
    sha256 = { alg = C.EVP_sha256(), length = 256/8  },
    sha384 = { alg = C.EVP_sha384(), length = 384/8  },
    sha512 = { alg = C.EVP_sha512(), length = 512/8  }
}

-- 64 is the max lenght and it covers up to sha512 algorithm
local digest_len = ffi_new("int[?]", 64)
local buf = ffi_new("char[?]", 64)


function _M.new(self)
    return setmetatable({}, mt)
end

local function getDigestAlgorithm(dtype)
    local md_name = available_algorithms[dtype]
    if ( md_name == nil ) then
        error("attempt to use unknown algorithm: '" .. dtype ..
                "'.\n Available algorithms are: sha1,sha224,sha256,sha384,sha512")
    end
    return md_name.alg, md_name.length
end

---
-- Returns the HMAC digest. The hashing algorithm is defined by the dtype parameter.
-- The optional raw flag, defaulted to false, is a boolean indicating whether the output should be a direct binary
-- equivalent of the HMAC or formatted as a hexadecimal string (the default)
--
-- @param self
-- @param dtype The hashing algorithm to use is specified by dtype
-- @param key The secret
-- @param msg The message to be signed
-- @param raw When true, it returns the binary format, else, the hex format is returned
--
function _M.digest(self, dtype, key, msg, raw)
    local evp_md, digest_length_int = getDigestAlgorithm(dtype)
    if key == nil or msg == nil then
        error("attempt to digest with a null key or message")
    end

    C.HMAC(evp_md, key, #key, msg, #msg, buf, digest_len)

    if raw == true then
        return ffi_str(buf,digest_length_int)
    end

    return resty_string.to_hex(ffi_str(buf,digest_length_int))
end


return _M