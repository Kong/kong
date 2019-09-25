local new_operation = require("kong.enterprise_edition.openapi2kong.operation")


local TYPE_NAME = ({...})[1]:match("kong.enterprise_edition.openapi2kong%.([^%.]+)$")  -- grab type-name from filename


local mt = require("kong.enterprise_edition.openapi2kong.common").create_mt(TYPE_NAME)


function mt:get_trace()
  return self.path
end


function mt:validate()

  if type(self.path) ~= "string" then
    return nil, ("a %s object expects a string as path, but got %s"):format(TYPE_NAME, type(self.path))
  end

  if type(self.spec) ~= "table" then
    return nil, ("a %s object expects a table as spec, but got %s"):format(TYPE_NAME, type(self.spec))
  end

  return true
end


function mt:post_validate()

  -- do validation after creation

  return true
end


-- returned object will have 'path' (string), 'servers' (servers-obj),
-- 'parameters' and 'operations' (array of operations_obj) properties
local function parse(path, spec, options, parent)

  local self = setmetatable({
    path = assert(path, "path argument is required"),
    spec = assert(spec, "spec argument is required"),
    parent = assert(parent, "parent argument is required"),
    options = options,
  }, mt)

  do
    local ok, err = self:dereference()
    if not ok then
      return ok, self:log_message(err)
    end
    -- prevent accidental access to non-dereferenced spec table
    spec = nil -- luacheck: ignore
  end

  local ok, err = self:validate()
  if not ok then
    return ok, self:log_message(err)
  end

  for _, property in ipairs { "servers", "parameters" } do
    local create_type = require("kong.enterprise_edition.openapi2kong." .. property)
    local sub_spec = self.spec[property]
    if sub_spec then
      local new_obj, err = create_type(sub_spec, options, self)
      if not new_obj then
        return nil, err
      end

      self[property] = new_obj
    end
  end

  self.operations = {}
  local known_methods = {
    get = true,
    put = true,
    post = true,
    delete = true,
    options = true,
    head = true,
    patch = true,
    trace = true,
  }
  for method, operation_spec in pairs(self.spec) do
    method = method:lower()
    if known_methods[method] then
      local operation_obj, err = new_operation(method, operation_spec, options, self)
      if not operation_obj then
        return nil, err
      end
      self.operations[#self.operations+1] = operation_obj
    end
  end

  ok, err = self:post_validate()
  if not ok then
    return ok, self:log_message(err)
  end

  return self
end


return parse
