local _M = {}


local cjson = require("cjson.safe")
local tostring = tostring
local tonumber = tonumber
local type = type
local fmt = string.format
local sub = string.sub
local cjson_encode = cjson.encode
local cjson_decode = cjson.decode


local TYPES_LOOKUP = {
    number  = 1,
    boolean = 2,
    string  = 3,
    table   = 4,
}


local marshallers = {
    shm_value = function(str_value, value_type)
        return fmt("%d:%s", value_type, str_value)
    end,

    [1] = function(number) -- number
        return tostring(number)
    end,

    [2] = function(bool)   -- boolean
        return bool and "true" or "false"
    end,

    [3] = function(str)    -- string
        return str
    end,

    [4] = function(t)      -- table
        local json, err = cjson_encode(t)
        if not json then
            return nil, "could not encode table value: " .. err
        end

        return json
    end,
}


function _M.marshall(value)
    if value == nil then
        return nil
    end

    local value_type = TYPES_LOOKUP[type(value)]

    if not marshallers[value_type] then
        error("cannot cache value of type " .. type(value))
    end

    local str_marshalled, err = marshallers[value_type](value)
    if not str_marshalled then
        return nil, "could not serialize value for LMDB insertion: "
                    .. err
    end

    return marshallers.shm_value(str_marshalled, value_type)
end


local unmarshallers = {
    shm_value = function(marshalled)
        local value_type = sub(marshalled, 1, 1)
        local str_value  = sub(marshalled, 3)

        return str_value, tonumber(value_type)
    end,

    [1] = function(str) -- number
        return tonumber(str)
    end,

    [2] = function(str) -- boolean
        return str == "true"
    end,

    [3] = function(str) -- string
        return str
    end,

    [4] = function(str) -- table
        local t, err = cjson_decode(str)
        if not t then
            return nil, "could not decode table value: " .. err
        end

        return t
    end,
}


function _M.unmarshall(v, err)
    if not v or err then
      -- this allows error/nil propagation in deserializing value from LMDB
      return nil, err
    end

    local str_serialized, value_type = unmarshallers.shm_value(v)

    local value, err = unmarshallers[value_type](str_serialized)
    if err then
        return nil, err
    end

    return value
end


return _M
