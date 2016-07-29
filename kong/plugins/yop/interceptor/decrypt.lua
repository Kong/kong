--
-- Created by IntelliJ IDEA.
-- User: zhangwenkang
-- Date: 16-7-23
-- Time: 下午12:04
-- To change this template use File | Settings | File Templates.
--
local decodeOnceToString = ngx.unescape_uri
local response, _ = require 'kong.yop.response'()

local stringy = require "stringy"
local json = require 'cjson'
local codec = require 'codec'

local _M = {}

local function blowfishDecrypt(body, secret)
    local pwd = codec.md5_encode(secret)
    local key = string.sub(pwd,1,16)
    local iv = string.sub(pwd,1,8)
    return codec.blowfish_encrypt(body, key, iv)
end

local function aesDecryptWithKeyBase64(body, secret)
    return codec.aes_decrypt(codec.base64_decode(body), codec.base64_decode(secret));
end
local function tryDecrypt(ctx)
    local keyStoreType = ctx.keyStoreType
    local secret = ctx.app.appSecret
    local parameters = ctx.parameters
    local body = parameters.encrypt

    local status,message
    if(keyStoreType == "CUST_BASED") then
        status,message = pcall(blowfishDecrypt,body, secret)
    else
        status,message = pcall(aesDecryptWithKeyBase64,body, secret)
    end

    -- 解密失败
    if(not status) then
        ngx.log(ngx.ERR,"decypty error!appKey:"..ctx.appKey)
        response.decryptException(ctx.appKey)
    end

    -- 解密成功,解析message
    local params = stringy.split(message, "&")
    local j = ""
    for _,value in pairs(params) do
        local kv = stringy.split(value, "=")
        if(table.getn(kv) ~= 2) then
            ngx.log(ngx.ERR,"the param from decryption error!appKey:"..ctx.appKey..";value:" .. value)
        else
            parameters[kv[1]] = decodeOnceToString(kv[2])
        end
    end
    ctx.parameters = parameters
end


_M.process = function(ctx)
    tryDecrypt(ctx)
end
return _M
