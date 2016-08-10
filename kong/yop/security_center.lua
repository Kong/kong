--
-- Created by IntelliJ IDEA.
-- User: jrk
-- Date: 16/8/3
-- Time: 下午3:43
-- To change this template use File | Settings | File Templates.
--
local codec = require 'codec'
local mcrypt = require 'mcrypt'

local response, _ = require 'kong.yop.response'()

local string = string
local os = os
local ngx = ngx

local _M = {}

function _M.blowfishDecrypt(body, secret)
    local pwd = codec.md5_encode(secret)
    local key = string.sub(pwd,1,16)
    local iv = string.sub(pwd,1,8)
    return mcrypt.bf_cfb_de(key, iv, codec.base64_decode(body))
end

function _M.aesDecryptWithKeyBase64(body, secret)
    return codec.aes_decrypt(codec.base64_decode(body), codec.base64_decode(secret));
end


function _M.validataSign(signBody,alg)
    if(alg == "SHA1") then
        return codec.sha1_encode(signBody),true
    end
    if(alg == "SHA256") then
        return codec.sha256_encode(signBody),true
    end
    if(alg == "MD5") then
        return codec.md5_encode(signBody),true
    end
end

local function sign(signBody,alg)
    if(alg == "SHA1") then
        return codec.sha1_encode(signBody)
    end
    if(alg == "SHA256") then
        return codec.sha256_encode(signBody)
    end
    if(alg == "MD5") then
        return codec.md5_encode(signBody)
    end
end

function _M.sign(trimBizResult)
    local appSercet = ngx.ctx.appSecret
    response.ts = os.time() * 1000
    return sign(appSercet..response.state..trimBizResult..response.ts..appSercet, ngx.ctx.alg)
end

local function blowfishEncrypt(body, secret)
    local pwd = codec.md5_encode(secret)
    local key = string.sub(pwd,1,16)
    local iv = string.sub(pwd,1,8)
    return mcrypt.bf_cfb_en(key, iv, body)
end

local function aesEncryptWithKeyBase64(body, secret)
    return codec.aes_encrypt(body, codec.base64_decode(secret));
end

function _M.encrypt(bizResult)
    local keyStoreType = ngx.ctx.keyStoreType
    local appSecret = ngx.ctx.appSecret
    if(keyStoreType == "CUST_BASED") then
        return codec.base64_encode(blowfishEncrypt(bizResult,appSecret))
    else
        return codec.base64_encode(aesEncryptWithKeyBase64(bizResult,appSecret))
    end
end

return _M