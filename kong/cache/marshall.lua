-------------------------------------------------------------------------------
-- NOTE: the following is copied from lua-resty-mlcache:                     --
------------------------------------------------------------------------ cut --
local codec
do
  local pok
  pok, codec = pcall(require, "string.buffer")
  if not pok then
    codec = require "cjson"
  end
end


local type = type
local pcall = pcall
local error = error
local tostring = tostring
local fmt = string.format
local now = ngx.now
local encode = codec.encode


local TYPES_LOOKUP = {
  number  = 1,
  boolean = 2,
  string  = 3,
  table   = 4,
}


local marshallers = {
  shm_value = function(str_value, value_type, at, ttl)
      return fmt("%d:%f:%f:%s", value_type, at, ttl, str_value)
  end,

  shm_nil = function(at, ttl)
      return fmt("0:%f:%f:", at, ttl)
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
      local pok, str = pcall(encode, t)
      if not pok then
          return nil, "could not encode table value: " .. str
      end

      return str
  end,
}


local function marshall_for_shm(value, ttl, neg_ttl)
  local at = now()

  if value == nil then
      return marshallers.shm_nil(at, neg_ttl), nil, true -- is_nil
  end

  -- serialize insertion time + Lua types for shm storage

  local value_type = TYPES_LOOKUP[type(value)]

  if not marshallers[value_type] then
      error("cannot cache value of type " .. type(value))
  end

  local str_marshalled, err = marshallers[value_type](value)
  if not str_marshalled then
      return nil, "could not serialize value for lua_shared_dict insertion: "
                  .. err
  end

  return marshallers.shm_value(str_marshalled, value_type, at, ttl)
end
------------------------------------------------------------------------ end --


return marshall_for_shm
