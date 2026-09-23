local _M = {}


local sha256_bin
do
  local digest = require "resty.openssl.digest"
  local sha256_digest

  function sha256_bin(key)
    local _, bin, err
    if not sha256_digest then
      sha256_digest, err = digest.new("sha256")
      if err then
        return nil, err
      end
    end

    bin, err = sha256_digest:final(key)
    if err then
      sha256_digest = nil
      return nil, err
    end

    _, err = sha256_digest:reset()
    if err then
      sha256_digest = nil
    end

    return bin
  end
end
_M.sha256_bin = sha256_bin


local sha256_hex, sha256_base64, sha256_base64url
do
  local to_hex       = require "resty.string".to_hex
  local to_base64    = ngx.encode_base64
  local to_base64url = require "ngx.base64".encode_base64url

  local function sha256_encode(encode_alg, key)
    local bin, err = sha256_bin(key)
    if err then
      return nil, err
    end

    return encode_alg(bin)
  end

  function sha256_hex(key)
    return sha256_encode(to_hex, key)
  end

  function sha256_base64(key)
    return sha256_encode(to_base64, key)
  end

  function sha256_base64url(key)
    return sha256_encode(to_base64url, key)
  end
end
_M.sha256_hex       = sha256_hex
_M.sha256_base64    = sha256_base64
_M.sha256_base64url = sha256_base64url


return _M
