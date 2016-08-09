--
-- Created by IntelliJ IDEA.
-- User: jrk
-- Date: 16/8/4
-- Time: 上午9:28
-- To change this template use File | Settings | File Templates.
--

local NULL = "<null>"
local response,_ = require 'kong.yop.response'()
local table = table
local string = string
local pairs = pairs

local changeLocationParam = {
    CODESRART = "codeStatus"      --  yop-center中这个变量在序列化成json串时位置会有变动
}

local _M = {}


local function concat(key,value,trimBizResult,bizResult)
    if value == nil then
        return trimBizResult,bizResult
    end
    if type(value) == 'number' or value:match("^%d+$") or value:sub(1,1) == '{' then               -- number,序列化后value是没有双引号的
        trimBizResult = table.concat({trimBizResult,"\"",key,"\":",value,","})        -- 去掉了"\n,\t,空格"这些东东
        bizResult = table.concat({bizResult,"\n  \"",key,"\" : ",value,","})
    else                                                                --  非number,序列化后value有双引号
        trimBizResult = table.concat({trimBizResult,"\"",key,"\":\"",value,"\","})     -- 去掉了"\n,\t,空格"这些东东
        bizResult = table.concat({bizResult,"\n  \"",key,"\" : \"",value,"\","})
    end
    return trimBizResult,bizResult
end

function _M.marshal(result,format)
    if not format then
        format = response.format
    end

    local finalInsert =  {}
    local bizResult = "{"
    local trimBizResult = "{"
    result = string.gsub(result,"%]","")             -- BankAuthResultDTO[a=1,b=2,c=<null>]"   ===>>>   BankAuthResultDTO[a=1,b=2,c=<null>
    for key,value in (result..","):gmatch("(%w+)=(.-),") do        -- 匹配出 key=value 这种格式的数据
        if value ~= NULL and not table.containKey(changeLocationParam,key) then
            trimBizResult,bizResult = concat(key,value,trimBizResult,bizResult)
        end
        if value ~= NULL and table.containKey(changeLocationParam,key)  then
            -- 记录下来,最后加到bizResult和trimBizResult中
            finalInsert[key] = value
        end
    end
    for key,value in pairs(finalInsert) do
        trimBizResult,bizResult = concat(key,value,trimBizResult,bizResult)
    end

    bizResult = bizResult:sub(1,-2)                -- 干掉字符串末尾最后一个 逗号
    trimBizResult = trimBizResult:sub(1,-2)
    bizResult = table.concat({bizResult,"\n}"})
    trimBizResult = table.concat({trimBizResult,"}"})

    return trimBizResult,bizResult      -- trimBizResult 用作签名,bizResult 用作加密
end

local function handleSubErrors(subErrors,_,body)
    if not subErrors then
        return _,body
    end

    local body = table.concat({body,"\n    \"subErrors\" : [ {"})
    local _ = table.concat({_,"\"subErrors\":[{"})
    for _,subError in pairs(subErrors) do
        -- error.subErrors.code
        _,body = concat("code",subError.code,_,body)
        -- error.subErrors.message
        _,body = concat("message",subError.message,_,body)

        body = body:sub(1,-2)                -- 干掉字符串末尾最后一个 逗号
        _ = _:sub(1,-2)
        body = table.concat({body,"\n    }, {"})
        _ = table.concat({_,"},{"})
    end

    body = body:sub(1,-10)                -- 干掉字符串末尾最后这些内容   '\n    }, {'
    _ = _:sub(1,-4)                       -- 干掉字符串末尾最后的这些内容   '},{'
    body = table.concat({body,"\n    } ],"})
    _ = table.concat({_,"}],"})
    return _,body
end

local function handleError(error,_,body)
    if not error then
        return _,body
    end
    local body = table.concat({body,"\n  \"error\" : {"})
    local _ = table.concat({_,"\"error:\"{"})
    -- error.code
    _,body = concat("code",error.code,_,body)
    -- error.message
    _,body = concat("message",error.message,_,body)
    -- error.subErrors
    _,body = handleSubErrors(error.subErrors,_,body)

    body = body:sub(1,-2)                -- 干掉字符串末尾最后一个 逗号
    _ = _:sub(1,-2)
    body = table.concat({body,"\n  },"})
    _ = table.concat({_ , "},"})
    return _,body
end

function _M.marshlResponse(resp)
    local body = "{"
    local _ = "{"

    -- state
    _,body = concat("state",resp.state,_,body)
    -- result
    _,body = concat("result",resp.result,_,body)
    -- ts
    _,body = concat("ts",resp.ts,_,body)
    -- sign
    _,body = concat("sign",resp.sign,_,body)
    -- error
    _,body = handleError(resp.error,_,body)
    -- stringResult
    _,body = concat("stringResult",resp.stringResult,_,body)
    -- format
    _,body = concat("format",resp.format,_,body)
    -- validSign
    _,body = concat("validSign",resp.validSign,_,body)

    body = body:sub(1,-2)                -- 干掉字符串末尾最后一个 逗号
    _ = _:sub(1,-2)
    body = table.concat({body,"\n}"})
    _ = table.concat({_,"}"})
    return body,_

end

return _M