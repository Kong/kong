local ffi = require("ffi")
local base = require("resty.core.base")
local clib = require("resty.kong.kproto.cdefs").clib

local get_string_buf = base.get_string_buf
local ffi_string = ffi.string

local err_buf_len = 1024
local err_buf = ffi.new("uint8_t[?]", err_buf_len)

local DEFAULT_SERIALIZATION_BUF_SIZE = 10240

local _M = {}

function _M.new()
    local hdl = clib.lua_resty_protobuf_trace_new()
    return hdl
end


function _M.get_serialized(hdl, trace_id)
    local buf = get_string_buf(DEFAULT_SERIALIZATION_BUF_SIZE)
    local rc = clib.lua_resty_protobuf_trace_get_serialized(hdl, buf, DEFAULT_SERIALIZATION_BUF_SIZE)

    assert(rc ~= 0, "failed to get serialized trace")

    local binary_data = ffi_string(buf, rc)
    return binary_data
end


function _M.enter_span(hdl, name)
    local rc = clib.lua_resty_protobuf_trace_enter_span(hdl, name, #name, err_buf, err_buf_len)

    if rc ~= 0 then
        return nil, ffi_string(err_buf, rc)
    end

    return true
end


function _M.exit_span(hdl)
    clib.lua_resty_protobuf_trace_exit_span(hdl)
end


function _M.add_string_attribute(hdl, key, value)
    local rc = clib.lua_resty_protobuf_trace_add_string_attribute(hdl, key, #key, value, #value, err_buf, err_buf_len)

    if rc ~= 0 then
        return nil, ffi_string(err_buf, rc)
    end

    return true
end


function _M.add_bool_attribute(hdl, key, value)
    local rc = clib.lua_resty_protobuf_trace_add_bool_attribute(hdl, key, #key, value and 1 or 0, err_buf, err_buf_len)

    if rc ~= 0 then
        return nil, ffi_string(err_buf, rc)
    end

    return true
end


function _M.add_int64_attribute(hdl, key, value)
    local rc = clib.lua_resty_protobuf_trace_add_int64_attribute(hdl, key, #key, value, err_buf, err_buf_len)

    if rc ~= 0 then
        return nil, ffi_string(err_buf, rc)
    end

    return true
end


function _M.add_double_attribute(hdl, key, value)
    local rc = clib.lua_resty_protobuf_trace_add_double_attribute(hdl, key, #key, value, err_buf, err_buf_len)

    if rc ~= 0 then
        return nil, ffi_string(err_buf, rc)
    end

    return true
end


return _M
