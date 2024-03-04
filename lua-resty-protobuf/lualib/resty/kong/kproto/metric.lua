local ffi = require("ffi")
local base = require("resty.core.base")
local clib = require("resty.kong.kproto.cdefs").clib

local math_floor = math.floor
local get_string_buf = base.get_string_buf
local ffi_string = ffi.string

local err_buf_len = 1024
local err_buf = ffi.new("uint8_t[?]", err_buf_len)

local DEFAULT_SERIALIZATION_BUF_SIZE = 10240

local _M = {}

function _M.new()
    local hdl = clib.lua_resty_protobuf_metrics_new()
    return hdl
end


function _M.get_serialized(hdl, trace_id)
    local buf = get_string_buf(DEFAULT_SERIALIZATION_BUF_SIZE)
    local rc = clib.lua_resty_protobuf_metrics_get_serialized(hdl, buf, DEFAULT_SERIALIZATION_BUF_SIZE)

    assert(rc > 0, "failed to get serialized metrics")

    local binary_data = ffi_string(buf, rc)
    return binary_data
end


function _M.add_gauge(hdl, key, value)
    local rc = clib.lua_resty_protobuf_metrics_add_gauge(hdl, key, #key, math_floor(value), err_buf, err_buf_len)

    if rc ~= 0 then
        return nil, ffi_string(err_buf, rc)
    end

    return true
end


function _M.add_sum(hdl, key, value)
    local rc = clib.lua_resty_protobuf_metrics_add_sum(hdl, key, #key, math_floor(value), err_buf, err_buf_len)

    if rc ~= 0 then
        return nil, ffi_string(err_buf, rc)
    end

    return true
end


return _M
