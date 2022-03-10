local bit = require "bit"


local byte = string.byte
local char = string.char
local band = bit.band
local bor = bit.bor
local lshift = bit.lshift
local rshift = bit.rshift
local tostring = tostring
local type = type


local _M = {
  _VERSION = "0.0.1"
}


-- frame format: Len(2 bytes) + Payload(max to 65535 bytes)


local MAX_PAYLOAD_LEN = 65535


local function uint16_to_bytes(num)
    if num < 0 or num > MAX_PAYLOAD_LEN then
      error("number " .. tostring(num) .. " out of range", 2)
    end

    return char(band(rshift(num, 8), 0xFF),
                band(num, 0xFF))
end


local function bytes_to_uint16(str)
    assert(#str == 2)

    local b1, b2 = byte(str, 1, 2)

    return bor(lshift(b1, 8), b2)
end


function _M.recv(sock)
    local data, err = sock:receive(2)
    if not data then
        return nil, "failed to receive the first 2 bytes: " .. err
    end

    local payload_len = bytes_to_uint16(data)

    data, err = sock:receive(payload_len)
    if not data then
        return nil, "failed to read payload: " .. (err or "unknown")
    end

    return data
end


function _M.send(sock, payload)
    if type(payload) ~= "string" then
        return nil, "payload must be string"
    end

    local payload_len = #payload

    if payload_len > MAX_PAYLOAD_LEN then
        return nil, "payload too big"
    end

    local bytes, err = sock:send(uint16_to_bytes(payload_len) .. payload)
    if not bytes then
        return nil, "failed to send frame: " .. err
    end

    return bytes
end


return _M
