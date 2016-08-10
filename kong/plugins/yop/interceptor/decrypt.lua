--
-- Created by IntelliJ IDEA.
-- User: zhangwenkang
-- Date: 16-7-23
-- Time: 下午12:04
-- To change this template use File | Settings | File Templates.
--
local decodeOnceToString = ngx.unescape_uri
local response, _ = require 'kong.yop.response'()
local security_center = require 'kong.yop.security_center'

local stringy = require "stringy"

local pcall = pcall
local ngx = ngx
local pairs = pairs
local table = table

local _M = {}

local function tryDecrypt(ctx)
    local keyStoreType = ctx.keyStoreType
    local secret = ctx.app.appSecret
    local parameters = ctx.parameters
    local body = parameters.encrypt
    if body then
        local status,message
        if(keyStoreType == "CUST_BASED") then
            status,message = pcall(security_center.blowfishDecrypt,body, secret)
        else
            status,message = pcall(security_center.aesDecryptWithKeyBase64,body, secret)
        end
        -- 解密失败
        if(not status) then
            ngx.log(ngx.ERR,"decypty error!appKey:"..ctx.appKey)
            response.decryptException(ctx.appKey)
        end

        -- 解密成功,解析message
        local params = stringy.split(message, "&")
        for _,value in pairs(params) do
            local kv = stringy.split(value, "=")
            if(table.getn(kv) ~= 2) then
                ngx.log(ngx.ERR,"the param from decryption error!appKey:"..ctx.appKey..";value:" .. value)
            else
                parameters[kv[1]] = decodeOnceToString(kv[2])
            end
        end
        ctx.parameters = parameters
    else
        ctx.parameters.encrypt = true        -- encrypt=true,表示无加密请求参数，但须加密返回
    end

end

_M.process = function(ctx)
    tryDecrypt(ctx)
end
return _M
