-- DAOs need more specific error objects, specifying if the error is due
-- to the schema, the database connection, a constraint violation etc, so the
-- caller can take actions based on the error type.
--
-- We will test this object and might create a KongError class too
-- if successful and needed.
--
-- Ideally, those errors could switch from having a type, to having an error
-- code.
--
-- @author thibaultcha

local error_mt = {}
error_mt.__index = error_mt

-- Returned the `message` property as a string if it is already one,
-- for format it as a string if it is a table.
-- @return the formatted `message` property
function error_mt:print_message()
  if type(self.message) == "string" then
    return self.message
  elseif type(self.message) == "table" then
    local errors = {}
    for k, v in pairs(self.message) do
      table.insert(errors, k..": "..v)
    end

    return table.concat(errors, " | ")
  end
end

-- Allow a DaoError to be printed
-- @return the formatted `message` property
function error_mt:__tostring()
  return self:print_message()
end

-- Allow a DaoError to be concatenated
-- @return the formatted and concatenated `message` property
function error_mt.__concat(a, b)
  if getmetatable(a) == error_mt then
    return a:print_message() .. b
  else
    return a .. b:print_message()
  end
end

local mt = {
  -- Constructor
  -- @param err A raw error, typically returned by lua-resty-cassandra (string)
  -- @param err_type An error type from constants, will be set as a key with 'true'
  --                 value on the returned error for fast comparison when dealing
  --                 with this error.
  -- @return A DaoError with the error_mt metatable
  __call = function (self, err, err_type)
    if err == nil then
      return nil
    end

    local t = {
      [err_type] = true,
      message = tostring(err)
    }

    return setmetatable(t, error_mt)
  end
}

return setmetatable({}, mt)
