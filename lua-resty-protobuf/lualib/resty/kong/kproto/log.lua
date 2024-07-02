local ffi = require("ffi")
local base = require("resty.core.base")
local clib = require("resty.kong.kproto.cdefs").clib

local get_string_buf = base.get_string_buf
local ffi_string = ffi.string

local err_buf_len = 1024
local err_buf = ffi.new("uint8_t[?]", err_buf_len)

local DEFAULT_SERIALIZATION_BUF_SIZE = 1024 * 1024 * 5 -- 5MB

local _M = {}

function _M.new()
    local hdl = clib.lua_resty_protobuf_logs_new()
    return hdl
end


function _M.get_serialized(hdl, trace_id)
    local buf = get_string_buf(DEFAULT_SERIALIZATION_BUF_SIZE)
    local rc = clib.lua_resty_protobuf_logs_get_serialized(hdl, buf, DEFAULT_SERIALIZATION_BUF_SIZE)

    assert(rc > 0, "failed to get serialized log")

    local binary_data = ffi_string(buf, rc)
    return binary_data
end


function _M.add_info(hdl, time_unix_nano, message)
    local rc = clib.lua_resty_protobuf_logs_add_info(hdl, time_unix_nano, message, #message, err_buf, err_buf_len)

    if rc ~= 0 then
        return nil, ffi_string(err_buf, rc)
    end

    return true
end


function _M.add_warn(hdl, time_unix_nano, message)
    local rc = clib.lua_resty_protobuf_logs_add_warn(hdl, time_unix_nano, message, #message, err_buf, err_buf_len)

    if rc ~= 0 then
        return nil, ffi_string(err_buf, rc)
    end

    return true
end


function _M.add_error(hdl, time_unix_nano, message)
    local rc = clib.lua_resty_protobuf_logs_add_error(hdl, time_unix_nano, message, #message, err_buf, err_buf_len)

    if rc ~= 0 then
        return nil, ffi_string(err_buf, rc)
    end

    return true
end


function _M.add_fatal(hdl, time_unix_nano, message)
    local rc = clib.lua_resty_protobuf_logs_add_fatal(hdl, time_unix_nano, message, #message, err_buf, err_buf_len)

    if rc ~= 0 then
        return nil, ffi_string(err_buf, rc)
    end

    return true
end


return _M
