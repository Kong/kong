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

local constants = require "kong.constants"

local error_mt = {}
error_mt.__index = error_mt

-- Allow a DaoError to be printed
-- @return the formatted `message` property
function error_mt:__tostring()
  return tostring(self.message)
end

-- Allow a DaoError to be concatenated
-- @return the formatted and concatenated `message` property
function error_mt.__concat(a, b)
  if getmetatable(a) == error_mt then
    return tostring(a)..b
  else
    return a..tostring(b)
  end
end

local mt = {
  -- Constructor
  -- @param `err`      A raw error, typically returned by lua-resty-cassandra (string)
  -- @param `err_type` An error type from constants, will be set as a key with 'true'
  --                   value on the returned error for fast comparison when dealing
  --                   with this error.
  -- @return           A DaoError with the error_mt metatable
  __call = function (self, err, err_type)
    if err == nil then
      return nil
    end

    local t = {
      is_dao_error = true,
      [err_type] = true,
      message = err
    }

    -- Cassandra server error
    if err_type == constants.DATABASE_ERROR_TYPES.DATABASE then
      t.message = "Cassandra error: "..t.message -- TODO remove once cassandra driver has nicer error messages
      t.cassandra_err_code = err.code
    end

    -- If message is a table, use the printable metatable
    if type(t.message) == "table" then
      local printable_mt = require "kong.tools.printable"
      setmetatable(t.message, printable_mt)
    end

    return setmetatable(t, error_mt)
  end
}

return setmetatable({}, mt)
