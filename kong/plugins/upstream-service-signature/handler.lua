local BasePlugin = require "kong.plugins.base_plugin"

local kong = kong
local ngx = ngx
local table_concat = table.concat

local BackSignHandler = BasePlugin:extend()

BackSignHandler.PRIORITY = 1000
BackSignHandler.VERSION = "0.1.0"

function BackSignHandler:new()
    BackSignHandler.super.new(self, "upstream-service-signature")
end

local function get_sign_content(key,time)
    local sign_tb = {
        'signature_key', '=', key, '&',
        'signature_time', '=', time
    }
    return table_concat(sign_tb)
end

local function get_sign_str(sign_content, sign_secret)
    local digest = ngx.hmac_sha1(sign_secret, sign_content)
    local signed_str = ngx.encode_base64(digest)
    return signed_str
end

--generate sign
local function gen_signature(key, secret, time)
    local sign_content = get_sign_content(key,time)
    local sign_str = get_sign_str(sign_content, secret)
    return sign_str
end

function BackSignHandler:access(config)
    BackSignHandler.super.access(self)
    local signature_key = config.signature_key
    local signature_secret = config.signature_secret
    local curr_time = ngx.time()
    local signature_sign = gen_signature(signature_key,signature_secret,curr_time)
    kong.service.request.set_header("X-Signature-Key", signature_key)
    kong.service.request.set_header("X-Signature-Time", curr_time)
    kong.service.request.set_header("X-Signature-Sign", signature_sign)
end

return BackSignHandler