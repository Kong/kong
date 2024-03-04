local ffi = require("ffi")
local math_floor = math.floor


-- From: https://github.com/openresty/lua-resty-signal/blob/master/lib/resty/signal.lua
local load_shared_lib
do
    local tostring = tostring
    local string_gmatch = string.gmatch
    local string_match = string.match
    local io_open = io.open
    local io_close = io.close
    local table_new = require("table.new")

    local cpath = package.cpath

    function load_shared_lib(so_name)
        local tried_paths = table_new(32, 0)
        local i = 1

        for k, _ in string_gmatch(cpath, "[^;]+") do
            local fpath = tostring(string_match(k, "(.*/)"))
            fpath = fpath .. so_name
            -- Don't get me wrong, the only way to know if a file exist is
            -- trying to open it.
            local f = io_open(fpath)
            if f ~= nil then
                io_close(f)
                return ffi.load(fpath, true)
            end

            tried_paths[i] = fpath
            i = i + 1
        end

        return nil, tried_paths
    end  -- function
end  -- do

local lib_name = ffi.os == "OSX" and "libresty_protobuf.dylib" or "libresty_protobuf.so"

local clib, tried_paths = load_shared_lib(lib_name)
if not clib then
    error(("could not load %s shared library from the following paths:\n"):format(lib_name) ..
          table.concat(tried_paths, "\n"), 2)
end

ffi.cdef([[
    void* lua_resty_protobuf_trace_new();
    void lua_resty_protobuf_trace_free(void* handle);

    void lua_resty_protobuf_trace_enter_span(void* handle, const char* name, uint64_t len);
    void lua_resty_protobuf_trace_add_string_attribute(void* handle, const char* name, uint64_t name_len, const char* val, uint64_t val_len);
    void lua_resty_protobuf_trace_add_bool_attribute(void* handle, const char* name, uint64_t name_len, int32_t val);
    void lua_resty_protobuf_trace_add_int64_attribute(void* handle, const char* name, uint64_t name_len, int64_t val);
    void lua_resty_protobuf_trace_add_double_attribute(void* handle, const char* name, uint64_t name_len, double val);
    void lua_resty_protobuf_trace_exit_span(void* handle);
    uint64_t lua_resty_protobuf_trace_get_serialized(void* handle, const char* buf, uint64_t buf_len);
]])


local _M = {}

function _M.new()
    local handle = clib.lua_resty_protobuf_trace_new()
    return handle
end

function _M.free(handle)
    clib.lua_resty_protobuf_trace_free(handle)
end

function _M.enter_span(handle, name)
    clib.lua_resty_protobuf_trace_enter_span(handle, name, #name)
end

function _M.add_string_attribute(handle, name, val)
    clib.lua_resty_protobuf_trace_add_string_attribute(handle, name, #name, val, #val)
end

function _M.add_bool_attribute(handle, name, val)
    clib.lua_resty_protobuf_trace_add_bool_attribute(handle, name, #name, val and 1 or 0)
end

function _M.add_int64_attribute(handle, name, val)
    clib.lua_resty_protobuf_trace_add_int64_attribute(handle, name, #name, val)
end

function _M.add_double_attribute(handle, name, val)
    clib.lua_resty_protobuf_trace_add_double_attribute(handle, name, #name, val)
end

function _M.exit_span(handle)
    clib.lua_resty_protobuf_trace_exit_span(handle)
end


local BUF_INIT_LEN = 4096
local BUF_MAX_LEN = 40960
local buf_cur_len = BUF_INIT_LEN
local buf = ffi.new("uint8_t[?]", buf_cur_len)

-- we are not going to call this function now
-- as we would like to send the data on the C-land,
-- cosocket is not fast enough.
function _M.get_serialized(handle)
    local sz = 0

    repeat
        sz = clib.lua_resty_protobuf_trace_get_serialized(handle, buf, buf_cur_len)

        if sz == 0 then
            buf_cur_len = buf_cur_len * 2
            buf = ffi.new("uint8_t[?]", buf_cur_len)
        end
    until sz ~= 0

    local serialized = ffi.string(buf, sz)

    if buf_cur_len > BUF_MAX_LEN then
        buf_cur_len = math_floor(buf_cur_len / 2)
        buf = ffi.new("uint8_t[?]", buf_cur_len)
    end

    return serialized
end


return _M
