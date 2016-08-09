--
-- Created by IntelliJ IDEA.
-- User: jrk
-- Date: 16/7/28
-- Time: 下午4:57
-- To change this template use File | Settings | File Templates.
--

local response, _ = require 'kong.yop.response'()
local security_center = require 'kong.yop.security_center'

local table = table
local string = string
local pairs = pairs
local ngx = ngx

function table.containKey(t, key)
    for _, v in pairs(t) do
        if key == v then
            return true
        end
    end
    return false
end

function string.trim(str)
    str = string.gsub(str, "^[ \t\n\r]+", "")
    return (string.gsub(str, "[ \t\n\r]+$", ""))
end

local function prepareSignParams(ctx)
    local ignoreSignFieldNames = {}
    table.insert(ignoreSignFieldNames,"sign")
    table.insert(ignoreSignFieldNames,"encrypt")

    local needSignKeys = {}
    for key,_ in pairs(ctx.parameters) do
        if not table.containKey(ignoreSignFieldNames,key) then
            -- 取出所有需要排序的key
            table.insert(needSignKeys,key)
        end
    end

    -- rest接口URI参与签名
    if string.sub(ctx.apiUri,1,6) == "/rest/" then
        table.insert(needSignKeys,"method")
        table.insert(needSignKeys,"v")
        ctx.parameters["method"] = ctx.apiUri
        local _,_,v = string.find(ctx.apiUri,"(v%d+%.?%d+)")       -- 匹配出版本号  v1.1     v1    v1.1234    v12.1234
        ctx.parameters["v"] = string.sub(v,2)
    end

    table.sort(needSignKeys)
    return needSignKeys
end

local function prepareSignBody(ctx,needSignKeys)
    local secret = ctx.app.appSecret
    local signBody = secret
    for _,value in pairs(needSignKeys) do
        signBody = signBody .. value .. string.trim(ctx.parameters[value])
    end
    return signBody .. secret
end

local function validateSign(ctx)
    local parameters = ctx.parameters
    local signRet = parameters.signRet     -- 客户端是否有过签名
    local sign = parameters.sign           -- 签名摘要
    local alg = ctx.api.signAlg            -- 签名算法
    if not signRet then
        return
    end
    local needSignKeys = prepareSignParams(ctx)
    local signBody = prepareSignBody(ctx,needSignKeys)
    local encodeBody
    local encodeBody,support = security_center.validataSign(signBody,alg)
    if(not support) then
        ngx.log(ngx.ERR,"不支持的签名算法!")
    end

    if encodeBody ~= sign then
        response.signExcepton(ctx.appKey)
    end
end

local _M = {}
_M.process = function(ctx)
    validateSign(ctx)
end
return _M