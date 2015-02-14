-- Implementation of CQL Binary protocol V2 available at:
-- https://git-wip-us.apache.org/repos/asf?p=cassandra.git;a=blob_plain;f=doc/native_protocol_v2.spec;hb=HEAD

local _M = {}

_M.version = "0.0.1"

local CQL_VERSION = "3.0.0"

--
-- PROTOCOL BITMASKS AND TYPES
--

local version_codes = {
    REQUEST=0x02,
    RESPONSE=0x82
}

local op_codes = {
    ERROR=0x00,
    STARTUP=0x01,
    READY=0x02,
    AUTHENTICATE=0x03,
    -- 0x04
    OPTIONS=0x05,
    SUPPORTED=0x06,
    QUERY=0x07,
    RESULT=0x08,
    PREPARE=0x09,
    EXECUTE=0x0A,
    REGISTER=0x0B,
    EVENT=0x0C,
    BATCH=0x0D,
    AUTH_CHALLENGE=0x0E,
    AUTH_RESPONSE=0x0F,
    AUTH_SUCCESS=0x10,
}

local consistency = {
    ANY=0x0000,
    ONE=0x0001,
    TWO=0x0002,
    THREE=0x0003,
    QUORUM=0x0004,
    ALL=0x0005,
    LOCAL_QUORUM=0x0006,
    EACH_QUORUM=0x0007,
    SERIAL=0x0008,
    LOCAL_SERIAL=0x0009,
    LOCAL_ONE=0x000A
}

_M.consistency = consistency

local query_flags = {
    VALUES=0x01,
    PAGE_SIZE=0x04,
    PAGING_STATE=0x08
}

local rows_flags = {
    GLOBAL_TABLES_SPEC=0x01,
    HAS_MORE_PAGES=0x02,
    -- 0x03
    NO_METADATA=0x04
}

local result_kinds = {
    VOID=0x01,
    ROWS=0x02,
    SET_KEYSPACE=0x03,
    PREPARED=0x04,
    SCHEMA_CHANGE=0x05
}

local error_codes = {
    [0x0000]= "Server error",
    [0x000A]= "Protocol error",
    [0x0100]= "Bad credentials",
    [0x1000]= "Unavailable exception",
    [0x1001]= "Overloaded",
    [0x1002]= "Is_bootstrapping",
    [0x1003]= "Truncate_error",
    [0x1100]= "Write_timeout",
    [0x1200]= "Read_timeout",
    [0x2000]= "Syntax_error",
    [0x2100]= "Unauthorized",
    [0x2200]= "Invalid",
    [0x2300]= "Config_error",
    [0x2400]= "Already_exists",
    [0x2500]= "Unprepared"
}

local types = {
    custom=0x00,
    ascii=0x01,
    bigint=0x02,
    blob=0x03,
    boolean=0x04,
    counter=0x05,
    decimal=0x06,
    double=0x07,
    float=0x08,
    int=0x09,
    text=0x0A,
    timestamp=0x0B,
    uuid=0x0C,
    varchar=0x0D,
    varint=0x0E,
    timeuuid=0x0F,
    inet=0x10,
    list=0x20,
    map=0x21,
    set=0x22
}

-- create functions for type annotations
for key, value in pairs(types) do
    _M[key] = function(value)
        return {type=key, value=value}
    end
end

_M.null = {type="null", value=nil}

-- see: http://en.wikipedia.org/wiki/Fisher-Yates_shuffle
local function shuffle(t)
    local n = #t
    while n >= 2 do
        -- n is now the last pertinent index
        local k = math.random(n) -- 1 <= k <= n
        -- Quick swap
        t[n], t[k] = t[k], t[n]
        n = n - 1
    end
    return t
end

---
--- SOCKET METHODS
---

local mt = { __index = _M }

function _M.new(self)
    math.randomseed(ngx and ngx.time() or os.time())

    local tcp
    if ngx and ngx.get_phase ~= nil and ngx.get_phase() ~= "init" then
        -- openresty
        tcp = ngx.socket.tcp
    else
        -- fallback to luasocket
        -- It's also a fallback for openresty in the
        -- "init" phase that doesn't support Cosockets
        tcp = require("socket").tcp
    end

    local sock, err = tcp()
    if not sock then
        return nil, err
    end

    return setmetatable({ sock = sock }, mt)
end

function _M.set_timeout(self, timeout)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    return sock:settimeout(timeout)
end

function _M.connect(self, contact_points, port)
    if port == nil then port = 9042 end
    if type(contact_points) == 'table' then
        shuffle(contact_points)
    else
        contact_points = {contact_points}
    end
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end
    local ok, err
    for _, host in ipairs(contact_points) do
        ok, err = sock:connect(host, port)
        if ok then
            self.host = host
            break
        end
    end
    if not ok then
        return false, err
    end
    if not self.initialized then
        --todo: not tested
        self:startup()
        self.initialized = true
    end
    return true
end

function _M.set_keepalive(self, ...)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    elseif sock.setkeepalive then
        return sock:setkeepalive(...)
    end
    return nil, "luasocket does not support reusable sockets"
end

function _M.get_reused_times(self)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    elseif sock.getreusedtimes then
        return sock:getreusedtimes()
    end
    return nil, "luasocket does not support reusable sockets"
end

local function close(self)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    return sock:close()
end

_M.close = close

---
--- ENCODE FUNCTIONS
---

local function big_endian_representation(num, bytes)
    if num < 0 then
        -- 2's complement
        num = math.pow(0x100, bytes) + num
    end
    local t = {}
    while num > 0 do
        local rest = math.fmod(num, 0x100)
        table.insert(t, 1, string.char(rest))
        num = (num-rest) / 0x100
    end
    local padding = string.rep(string.char(0), bytes - #t)
    return padding .. table.concat(t)
end

local function int_representation(num)
    return big_endian_representation(num, 4)
end

local function short_representation(num)
    return big_endian_representation(num, 2)
end

local function bigint_representation(n)
    local first_byte
    if n >= 0 then
        first_byte = 0
    else
        first_byte = 0xFF
    end

    return string.char(first_byte, -- only 53 bits from double
                       math.floor(n / 0x1000000000000) % 0x100,
                       math.floor(n / 0x10000000000) % 0x100,
                       math.floor(n / 0x100000000) % 0x100,
                       math.floor(n / 0x1000000) % 0x100,
                       math.floor(n / 0x10000) % 0x100,
                       math.floor(n / 0x100) % 0x100,
                       n % 0x100)
end

local function uuid_representation(value)
    local str = string.gsub(value, "-", "")
    local buffer = {}
    for i = 1, #str, 2 do
        local byte_str =  string.sub(str, i, i + 1)
        buffer[#buffer + 1] = string.char(tonumber(byte_str, 16))
    end
    return table.concat(buffer)
end

local function string_representation(str)
    return short_representation(#str) .. str
end

local function long_string_representation(str)
    return int_representation(#str) .. str
end

local function bytes_representation(bytes)
    return int_representation(#bytes) .. bytes
end

local function short_bytes_representation(bytes)
    return short_representation(#bytes) .. bytes
end

local function string_map_representation(map)
    local buffer = {}
    local n = 0
    for k, v in pairs(map) do
        buffer[#buffer + 1] = string_representation(k)
        buffer[#buffer + 1] = string_representation(v)
        n = n + 1
    end
    return short_representation(n) .. table.concat(buffer)
end

local function boolean_representation(value)
    if value then return "\001" else return "\000" end
end

-- 'inspired' by https://github.com/fperrad/lua-MessagePack/blob/master/src/MessagePack.lua
local function double_representation(number)
    local sign = 0
    if number < 0.0 then
        sign = 0x80
        number = -number
    end
    local mantissa, exponent = math.frexp(number)
    if mantissa ~= mantissa then
        return string.char(0xFF, 0xF8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00) -- nan
    elseif mantissa == math.huge then
      if sign == 0 then
          return string.char(0x7F, 0xF0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00) -- +inf
      else
          return string.char(0xFF, 0xF0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00) -- -inf
      end
    elseif mantissa == 0.0 and exponent == 0 then
        return string.char(sign, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00) -- zero
    else
        exponent = exponent + 0x3FE
        mantissa = (mantissa * 2.0 - 1.0) * math.ldexp(0.5, 53)
        return string.char(sign + math.floor(exponent / 0x10),
              (exponent % 0x10) * 0x10 + math.floor(mantissa / 0x1000000000000),
              math.floor(mantissa / 0x10000000000) % 0x100,
              math.floor(mantissa / 0x100000000) % 0x100,
              math.floor(mantissa / 0x1000000) % 0x100,
              math.floor(mantissa / 0x10000) % 0x100,
              math.floor(mantissa / 0x100) % 0x100,
              mantissa % 0x100)
    end
end

local function float_representation(number)
    if number == 0 then
        return string.char(0x00, 0x00, 0x00, 0x00)
    elseif number ~= number then
        return string.char(0xFF, 0xFF, 0xFF, 0xFF)
    else
        local sign = 0x00
        if number < 0 then
            sign = 0x80
            number = -number
        end
        local mantissa, exponent = math.frexp(number)
        exponent = exponent + 0x7F
        if exponent <= 0 then
            mantissa = math.ldexp(mantissa, exponent - 1)
            exponent = 0
        elseif exponent > 0 then
            if exponent >= 0xFF then
                return string.char(sign + 0x7F, 0x80, 0x00, 0x00)
            elseif exponent == 1 then
                exponent = 0
            else
                mantissa = mantissa * 2 - 1
                exponent = exponent - 1
            end
        end
        mantissa = math.floor(math.ldexp(mantissa, 23) + 0.5)
        return string.char(
                sign + math.floor(exponent / 2),
                (exponent % 2) * 0x80 + math.floor(mantissa / 0x10000),
                math.floor(mantissa / 0x100) % 0x100,
                mantissa % 0x100)
    end
end

local function inet_representation(value)
    local digits = {}
    -- ipv6
    for d in string.gmatch(value, "([^:]+)") do
        if #d == 4 then
            for i = 1, #d, 2 do
                digits[#digits + 1] = string.char(tonumber(string.sub(d, i, i + 1), 16))
            end
        end
    end
    -- ipv4
    if #digits == 0 then
        for d in string.gmatch(value, "(%d+)") do
            table.insert(digits, string.char(d))
        end
    end
    return table.concat(digits)
end

local function list_representation(elements)
    local buffer = {short_representation(#elements)}
    for _, value in ipairs(elements) do
        buffer[#buffer + 1] = _M._value_representation(value, true)
    end
    return table.concat(buffer)
end

local function set_representation(elements)
    return list_representation(elements)
end

local function map_representation(map)
    local buffer = {}
    local size = 0
    for key, value in pairs(map) do
        buffer[#buffer + 1] = _M._value_representation(key, true)
        buffer[#buffer + 1] = _M._value_representation(value, true)
        size = size + 1
    end
    table.insert(buffer, 1, short_representation(size))
    return table.concat(buffer)
end

local function identity_representation(value)
    return value
end

local packers = {
    -- custom=0x00,
    [types.ascii]=identity_representation,
    [types.bigint]=bigint_representation,
    [types.blob]=identity_representation,
    [types.boolean]=boolean_representation,
    [types.counter]=bigint_representation,
    -- decimal=0x06,
    [types.double]=double_representation,
    [types.float]=float_representation,
    [types.int]=int_representation,
    [types.text]=identity_representation,
    [types.timestamp]=bigint_representation,
    [types.uuid]=uuid_representation,
    [types.varchar]=identity_representation,
    [types.varint]=int_representation,
    [types.timeuuid]=uuid_representation,
    [types.inet]=inet_representation,
    [types.list]=list_representation,
    [types.map]=map_representation,
    [types.set]=set_representation
}

local function infer_type(value)
    if type(value) == 'number' and math.floor(value) == value then
        return types.int
    elseif type(value) == 'number' then
        return types.float
    elseif type(value) == 'boolean' then
        return types.boolean
    elseif type(value) == 'table' and value.type == 'null' then
        return _M.null
    elseif type(value) == 'table' and value.type then
        return types[value.type]
    else
        return types.varchar
    end
end

local function value_representation(value, short)
    local infered_type = infer_type(value)
    if type(value) == 'table' and value.type and value.value then
        value = value.value
    end
    if infered_type == _M.null then
        if short then
            return short_representation(-1)
        else
            return int_representation(-1)
        end
    end
    local representation = packers[infered_type](value)
    if short then
        return short_bytes_representation(representation)
    end
    return bytes_representation(representation)
end

_M._value_representation = value_representation

local function values_representation(args)
    if not args then
        return ""
    end
    local values = {}
    values[#values + 1] = short_representation(#args)
    for _, value in ipairs(args) do
        values[#values + 1] = value_representation(value)
    end
    return table.concat(values)
end

---
--- DECODE FUNCTIONS
---

local function create_buffer(str)
    return {str=str, pos=1}
end

local function string_to_number(str, signed)
    local number = 0
    local exponent = 1
    for i = #str, 1, -1 do
        number = number + string.byte(str, i) * exponent
        exponent = exponent * 256
    end
    if signed and number > exponent / 2 then
        -- 2's complement
        number = number - exponent
    end
    return number
end

local function read_signed_number(bytes)
    return string_to_number(bytes, true)
end

local function read_raw_bytes(buffer, n_bytes)
    local bytes = string.sub(buffer.str, buffer.pos, buffer.pos + n_bytes - 1)
    buffer.pos = buffer.pos + n_bytes
    return bytes
end

local function read_raw_byte(buffer)
    return string.byte(read_raw_bytes(buffer, 1))
end

local function read_int(buffer)
    return string_to_number(read_raw_bytes(buffer, 4), true)
end

local function read_short(buffer)
    return string_to_number(read_raw_bytes(buffer, 2), false)
end

local function read_string(buffer)
    local str_size = read_short(buffer)
    return read_raw_bytes(buffer, str_size)
end

local function read_bytes(buffer)
    local size = read_int(buffer, true)
    if size < 0 then
        return nil
    end
    return read_raw_bytes(buffer, size)
end

local function read_short_bytes(buffer)
    local size = read_short(buffer)
    return read_raw_bytes(buffer, size)
end

local function read_option(buffer)
    local type_id = read_short(buffer)
    local type_value = nil
    if type_id == types.custom then
        type_value = read_string(buffer)
    elseif type_id == types.list then
        type_value = read_option(buffer)
    elseif type_id == types.map then
        type_value = {read_option(buffer), read_option(buffer)}
    elseif type_id == types.set then
        type_value = read_option(buffer)
    end
    return {id=type_id, value=type_value}
end

local function read_boolean(bytes)
    return string.byte(bytes) == 1
end

local function read_bigint(bytes)
    local b1, b2, b3, b4, b5, b6, b7, b8 = string.byte(bytes, 1, 8)
    if b1 < 0x80 then
        return ((((((b1 * 0x100 + b2) * 0x100 + b3) * 0x100 + b4) * 0x100 + b5) * 0x100 + b6) * 0x100 + b7) * 0x100 + b8
    else
        return ((((((((b1 - 0xFF) * 0x100 + (b2 - 0xFF)) * 0x100 + (b3 - 0xFF)) * 0x100 + (b4 - 0xFF)) * 0x100 + (b5 - 0xFF)) * 0x100 + (b6 - 0xFF)) * 0x100 + (b7 - 0xFF)) * 0x100 + (b8 - 0xFF)) - 1
    end
end

local function read_double(bytes)
    local b1, b2, b3, b4, b5, b6, b7, b8 = string.byte(bytes, 1, 8)
    local sign = b1 > 0x7F
    local exponent = (b1 % 0x80) * 0x10 + math.floor(b2 / 0x10)
    local mantissa = ((((((b2 % 0x10) * 0x100 + b3) * 0x100 + b4) * 0x100 + b5) * 0x100 + b6) * 0x100 + b7) * 0x100 + b8
    if sign then
        sign = -1
    else
        sign = 1
    end
    local number
    if mantissa == 0 and exponent == 0 then
        number = sign * 0.0
    elseif exponent == 0x7FF then
        if mantissa == 0 then
            number = sign * math.huge
        else
            number = 0.0/0.0
        end
    else
        number = sign * math.ldexp(1.0 + mantissa / 0x10000000000000, exponent - 0x3FF)
    end
    return number
end

local function read_float(bytes)
    local b1, b2, b3, b4 = string.byte(bytes, 1, 4)
    local exponent = (b1 % 0x80) * 0x02 + math.floor(b2 / 0x80)
    local mantissa = math.ldexp(((b2 % 0x80) * 0x100 + b3) * 0x100 + b4, -23)
    if exponent == 0xFF then
        if mantissa > 0 then
            return 0 / 0
        else
            mantissa = math.huge
            exponent = 0x7F
        end
    elseif exponent > 0 then
        mantissa = mantissa + 1
    else
        exponent = exponent + 1
    end
    if b1 >= 0x80 then
        mantissa = -mantissa
    end
    return math.ldexp(mantissa, exponent - 0x7F)
end

local function read_uuid(bytes)
    local buffer = {}
    for i = 1, #bytes do
        buffer[i] = string.format("%02x", string.byte(bytes, i))
    end
    table.insert(buffer, 5, "-")
    table.insert(buffer, 8, "-")
    table.insert(buffer, 11, "-")
    table.insert(buffer, 14, "-")
    return table.concat(buffer)
end

local function read_inet(bytes)
    local buffer = {}
    if #bytes == 16 then
        -- ipv6
        for i = 1, #bytes, 2 do
            buffer[#buffer + 1] = string.format("%02x", string.byte(bytes, i)) ..
                                  string.format("%02x", string.byte(bytes, i + 1))
        end
        return table.concat(buffer, ":")
    end
    for i = 1, #bytes do
        buffer[#buffer + 1] = string.format("%d", string.byte(bytes, i))
    end
    return table.concat(buffer, ".")
end

local function read_list(bytes, type)
    local element_type = type.value
    local buffer = create_buffer(bytes)
    local n = read_short(buffer)
    local elements = {}
    for i = 1, n do
        elements[#elements + 1] = _M._read_value(buffer, element_type, true)
    end
    return elements
end

local read_set = read_list

local function read_map(bytes, type)
    local key_type = type.value[1]
    local value_type = type.value[2]
    local buffer = create_buffer(bytes)
    local n = read_short(buffer)
    local map = {}
    for i = 1, n do
        local key = _M._read_value(buffer, key_type, true)
        local value = _M._read_value(buffer, value_type, true)
        map[key] = value
    end
    return map
end

local unpackers = {
    -- custom=0x00,
    [types.ascii]=identity_representation,
    [types.bigint]=read_bigint,
    [types.blob]=identity_representation,
    [types.boolean]=read_boolean,
    [types.counter]=read_bigint,
    -- decimal=0x06,
    [types.double]=read_double,
    [types.float]=read_float,
    [types.int]=read_signed_number,
    [types.text]=identity_representation,
    [types.timestamp]=read_bigint,
    [types.uuid]=read_uuid,
    [types.varchar]=identity_representation,
    [types.varint]=read_signed_number,
    [types.timeuuid]=read_uuid,
    [types.inet]=read_inet,
    [types.list]=read_list,
    [types.map]=read_map,
    [types.set]=read_set
}

local function read_value(buffer, type, short)
    local bytes
    if short then
        bytes = read_short_bytes(buffer)
    else
        bytes = read_bytes(buffer)
    end
    if bytes == nil then
        return nil
    end
    return unpackers[type.id](bytes, type)
end

_M._read_value = read_value

local function read_error(buffer)
    local error_code = error_codes[read_int(buffer)]
    local error_message = read_string(buffer)
    return 'Cassandra returned error (' .. error_code .. '): "' .. error_message .. '"'
end

local function read_frame(self, tracing)
    local header, err, partial = self.sock:receive(8)
    if not header then
        return nil, string.format("Failed to read frame header from %s: %s", self.host, err)
    end
    local header_buffer = create_buffer(header)
    local version = read_raw_byte(header_buffer)
    local flags = read_raw_byte(header_buffer)
    local stream = read_raw_byte(header_buffer)
    local op_code = read_raw_byte(header_buffer)
    local length = read_int(header_buffer)
    local body, err, partial, tracing_id
    if length > 0 then
        body, err, partial = self.sock:receive(length)
        if not body then
            return nil, string.format("Failed to read frame body from %s: %s", self.host, err)
        end
    else
        body = ""
    end
    if version ~= version_codes.RESPONSE then
        error("Invalid response version")
    end
    local body_buffer = create_buffer(body)
    if flags == 0x02 then -- tracing
        tracing_id = read_uuid(string.sub(body, 1, 16))
        body_buffer.pos = 17
    end
    if op_code == op_codes.ERROR then
        return nil, read_error(body_buffer)
    end
    return {
        flags=flags,
        stream=stream,
        op_code=op_code,
        buffer=body_buffer,
        tracing_id=tracing_id
    }
end

---
--- BITS methods
--- http://ricilake.blogspot.com.br/2007/10/iterating-bits-in-lua.html
---

local function hasbit(x, p)
  return x % (p + p) >= p
end

local function setbit(x, p)
  return hasbit(x, p) and x or x + p
end

---
--- CLIENT METHODS
---

local function send_frame_and_get_response(self, op_code, body, tracing)
    local version = string.char(version_codes.REQUEST)
    local flags = tracing and '\002' or '\000'
    local stream_id = '\000'
    local length = int_representation(#body)
    local frame = version .. flags .. stream_id .. string.char(op_code) .. length .. body

    local bytes, err = self.sock:send(frame)
    if not bytes then
        return nil, string.format("Failed to read frame header from %s: %s", self.host, err)
    end
    return read_frame(self)
end

function _M.startup(self)
    local body = string_map_representation({["CQL_VERSION"]=CQL_VERSION})
    local response, err = send_frame_and_get_response(self, op_codes.STARTUP, body)
    if not response then
        return nil, err
    end
    if response.op_code ~= op_codes.READY then
        error("Server is not ready")
    end
    return true
end

local function parse_metadata(buffer)
    -- Flags parsing
    local flags = read_int(buffer)
    local global_tables_spec = hasbit(flags, rows_flags.GLOBAL_TABLES_SPEC)
    local has_more_pages = hasbit(flags, rows_flags.HAS_MORE_PAGES)
    local columns_count = read_int(buffer)

    -- Paging metadata
    local paging_state
    if has_more_pages then
        paging_state = read_bytes(buffer)
    end

    -- global_tables_spec metadata
    local global_keyspace_name, global_table_name
    if global_tables_spec then
        global_keyspace_name = read_string(buffer)
        global_table_name = read_string(buffer)
    end

    -- Columns metadata
    local columns = {}
    for j = 1, columns_count do
        local ksname = global_keyspace_name
        local tablename = global_table_name
        if not global_tables_spec then
            ksname = read_string(buffer)
            tablename = read_string(buffer)
        end
        local column_name = read_string(buffer)
        columns[#columns + 1] = {
            keyspace = ksname,
            table = tablename,
            name = column_name,
            type = read_option(buffer)
        }
    end

    return {
        columns_count=columns_count,
        columns=columns,
        has_more_pages=has_more_pages,
        paging_state=paging_state
    }
end

local function parse_rows(buffer, metadata)
    local columns = metadata.columns
    local columns_count = metadata.columns_count
    local rows_count = read_int(buffer)
    local values = {}
    local row_mt = {
      __index = function(t, i)
        -- allows field access by position/index, not column name only
        local column = columns[i]
        if column then
          return t[column.name]
        end
        return nil
      end,
      __len = function() return columns_count end
    }
    for i = 1, rows_count do
        local row = {}
        setmetatable(row, row_mt)
        for j = 1, columns_count do
            local value = read_value(buffer, columns[j].type)
            row[columns[j].name] = value
        end
        values[#values + 1] = row
    end
    assert(buffer.pos == #(buffer.str) + 1)
    return values
end

local batch_statement = {
  __index = {
    add = function(self, query, args)
      table.insert(self.queries, {query=query, args=args})
    end,
    representation = function(self)
      local b = {}
      b[#b + 1] = string.char(0) -- todo: logged/unlogged/counter
      b[#b + 1] = short_representation(#self.queries)
      for _, query in ipairs(self.queries) do
        local kind
        local string_or_id
        if type(query.query) == "string" then
          kind = string.char("0")
          string_or_id = long_string_representation(query.query)
        else
          kind = string.char("1")
          string_or_id = short_bytes_representation(query.query.id)
        end
        b[#b + 1] = kind .. string_or_id .. values_representation(query.args)
      end
      return table.concat(b)
    end
  }
}

function _M.BatchStatement(self)
  return setmetatable({queries={}}, batch_statement)
end

function _M.prepare(self, query, options)
    if not options then options = {} end
    local body = long_string_representation(query)
    local response, err = send_frame_and_get_response(self, op_codes.PREPARE, body, options.tracing)
    if not response then
        return nil, err
    end
    if response.op_code ~= op_codes.RESULT then
        error("Result expected")
    end
    local buffer = response.buffer
    local kind = read_int(buffer)
    local result = {}
    if kind == result_kinds.PREPARED then
        local id = read_short_bytes(buffer)
        local metadata = parse_metadata(buffer)
        local result_metadata = parse_metadata(buffer)
        assert(buffer.pos == #(buffer.str) + 1)
        result = {
            type="PREPARED",
            id=id,
            metadata=metadata,
            result_metadata=result_metadata
        }
    else
        error("Invalid result kind")
    end
    if response.tracing_id then result.tracing_id = response.tracing_id end
    return result
end

-- Default query options
local default_options = {
    consistency_level=consistency.ONE,
    page_size=5000,
    auto_paging=false
}

function _M.execute(self, query, args, options)
    if not options then options = {} end

    -- Default options
    for k,v in pairs(default_options) do
        if options[k] == nil then
            options[k] = v
        end
    end

    if options.auto_paging then
        local page = 0
        return function(query, paging_state)
            local rows, err = self:execute(query, args, {
                page_size=options.page_size,
                paging_state=paging_state
            })
            page = page + 1
            return rows.meta.paging_state, rows, page
        end, query, nil
    end

    -- Determine if query is a query, statement, or batch
    local op_code, query_repr
    if type(query) == "string" then
        op_code = op_codes.QUERY
        query_repr = long_string_representation(query)
    elseif getmetatable(query) == batch_statement then
        op_code = op_codes.BATCH
        query_repr = query:representation()
    else
        op_code = op_codes.EXECUTE
        query_repr = short_bytes_representation(query.id)
    end

    -- Flags of the <query_parameters>
    local flags_repr = 0

    if args then
        flags_repr = setbit(flags_repr, query_flags.VALUES)
    end

    local result_page_size = ""
    if options.page_size > 0 then
        flags_repr = setbit(flags_repr, query_flags.PAGE_SIZE)
        result_page_size = int_representation(options.page_size)
    end

    local paging_state = ""
    if options.paging_state then
        flags_repr = setbit(flags_repr, query_flags.PAGING_STATE)
        paging_state = bytes_representation(options.paging_state)
    end

    -- <query_parameters>: <consistency><flags>[<value><...>][<result_page_size>][<paging_state>]
    local query_parameters = short_representation(options.consistency_level) .. string.char(flags_repr) .. values_representation(args) .. result_page_size .. paging_state

    -- frame body: <query><query_parameters>
    local frame_body = query_repr .. query_parameters

    -- Send frame
    local response, err = send_frame_and_get_response(self, op_code, frame_body, options.tracing)

    -- Check response errors
    if not response then
        return nil, err
    elseif response.op_code ~= op_codes.RESULT then
        error("Result expected")
    end

    -- Parse response
    local result
    local buffer = response.buffer
    local kind = read_int(buffer)
    if kind == result_kinds.VOID then
        result = {
            type="VOID"
        }
    elseif kind == result_kinds.ROWS then
        local metadata = parse_metadata(buffer)
        result = parse_rows(buffer, metadata)
        result.type = "ROWS"
        result.meta = {
            has_more_pages=metadata.has_more_pages,
            paging_state=metadata.paging_state
        }
    elseif kind == result_kinds.SET_KEYSPACE then
        result = {
            type="SET_KEYSPACE",
            keyspace=read_string(buffer)
        }
    elseif kind == result_kinds.SCHEMA_CHANGE then
        result = {
            type="SCHEMA_CHANGE",
            change=read_string(buffer),
            keyspace=read_string(buffer),
            table=read_string(buffer)
        }
    else
        error(string.format("Invalid result kind: %x", kind))
    end

    if response.tracing_id then
        result.tracing_id = response.tracing_id
    end

    return result
end

function _M.set_keyspace(self, keyspace_name)
    return self:execute("USE " .. keyspace_name)
end

function _M.get_trace(self, result)
    if not result.tracing_id then
        return nil, "No tracing available"
    end
    local rows, err = self:execute([[
        SELECT coordinator, duration, parameters, request, started_at
          FROM  system_traces.sessions WHERE session_id = ?]],
        {_M.uuid(result.tracing_id)})
    if not rows then
        return nil, "Unable to get trace: " .. err
    end
    if #rows == 0 then
        return nil, "Trace not found"
    end
    local trace = rows[1]
    trace.events, err = self:execute([[
        SELECT event_id, activity, source, source_elapsed, thread
          FROM system_traces.events WHERE session_id = ?]],
        {_M.uuid(result.tracing_id)})
    if not trace.events then
        return nil, "Unable to get trace events: " .. err
    end
    return trace
end

return _M
