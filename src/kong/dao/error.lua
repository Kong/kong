-- DAOs need more specific error objects, specifying if the error is due to the schema, the database connection,
-- a constraint violation etc... We will test this object and might create a KongError class too if successful and needed.

local error_mt = {}
error_mt.__index = error_mt

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

function error_mt:__tostring()
  return self:print_message()
end

function error_mt.__concat(a, b)
  if getmetatable(a) == error_mt then
    return a:print_message() .. b
  else
    return a .. b:print_message()
  end
end

local mt = {
  __index = DaoError,
  __call = function (self, err, type)
    if err == nil then
      return nil
    end

    local t = {
      [type] = true,
      message = err
    }

    return setmetatable(t, error_mt)
  end
}

return setmetatable({}, mt)
