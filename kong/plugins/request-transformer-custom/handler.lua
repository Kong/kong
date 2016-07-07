local BasePlugin = require "kong.plugins.base_plugin"
local req_set_uri_args = ngx.req.set_uri_args
local req_get_uri_args = ngx.req.get_uri_args
local req_set_header = ngx.req.set_header
local req_get_headers = ngx.req.get_headers
local req_read_body = ngx.req.read_body
local req_set_body_data = ngx.req.set_body_data
local req_get_body_data = ngx.req.get_body_data
local encode_args = ngx.encode_args
local ngx_decode_args = ngx.decode_args
local string_len = string.len
local string_find = string.find

local CONTENT_LENGTH = "content-length"
local CONTENT_TYPE = "content-type"
local JSON, MULTI, ENCODED = "json", "multi_part", "form_encoded"

local function get_content_type(content_type)
    if content_type == nil then
        return
    end
    if string_find(content_type:lower(), "application/json", nil, true) then
        return JSON
    elseif string_find(content_type:lower(), "multipart/form-data", nil, true) then
        return MULTI
    elseif string_find(content_type:lower(), "application/x-www-form-urlencoded", nil, true) then
        return ENCODED
    end
end

local function decode_args(body)
    if body then
        return ngx_decode_args(body)
    end
    return {}
end

local RequestTransformerCustomHandler = BasePlugin:extend()

function RequestTransformerCustomHandler:new()
    RequestTransformerCustomHandler.super.new(self, "request-transformer-custom")
end

function RequestTransformerCustomHandler:access(conf)
    RequestTransformerCustomHandler.super.access(self)
    if not conf.transform then return end;

    local querystring = req_get_uri_args()
    for name, value in pairs(conf.transform) do
        if querystring[name] then
            querystring[value] = querystring[name]
            querystring[name] = nil
        end
    end
    req_set_uri_args(querystring)

    local content_type_value = req_get_headers()[CONTENT_TYPE]
    local content_type = get_content_type(content_type_value)
    if content_type == nil then return end

    -- Call req_read_body to read the request body first
    req_read_body()
    local body = req_get_body_data()
    local content_length = (body and string_len(body)) or 0

    if content_type == ENCODED then
        local parameters = decode_args(body)
        if content_length > 0 then
            for name, value in pairs(conf.transform) do
                if parameters[name] then
                    parameters[value] = parameters[name]
                    parameters[name] = nil
                end
            end
        end

        body = encode_args(parameters);
        req_set_body_data(body)
        req_set_header(CONTENT_LENGTH, string_len(body))
    end
end

RequestTransformerCustomHandler.PRIORITY = 800
return RequestTransformerCustomHandler
