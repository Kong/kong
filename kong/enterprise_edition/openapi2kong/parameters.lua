local TYPE_NAME = ({...})[1]:match("kong.enterprise_edition.openapi2kong%.([^%.]+)$")  -- grab type-name from filename

local mt = require("kong.enterprise_edition.openapi2kong.common").create_mt(TYPE_NAME)


function mt:get_trace()
  return ""
end


function mt:validate()

  if type(self.spec) ~= "table" then
    return nil, ("a %s object expects a table as spec, but got %s"):format(TYPE_NAME, type(self.spec))
  end

  return true
end


function mt:post_validate()

  -- do validation after creation

  return true
end


-- Iterate over all parameters applicable.
-- This includes the parameters defined at `path` level, and possibly overridden
-- on the `operation` level.
function mt:iterate()

  local list
  if self.parent.type == "path" then
    -- no inherited ones
    list = self
  else
    -- we're at the `operation` level and must take inherited ones into account
    local operation = self.parent
    assert(operation.type == "operation", "expected an operation object, got "
                                          .. tostring(operation.type))
    list = {}
    local duplicates = {}
    for i, param in ipairs(self) do
      list[i] = param
      duplicates[param:get_id()] = true
    end
    local path = operation.parent
    assert(path.type == "path", "expected a path object, got "
                                .. tostring(path.type))
    for _, param in ipairs(path.parameters or {}) do
      local id = param:get_id()
      if not duplicates[id] then
        list[#list+1] = param
        duplicates[id] = true
      end
    end
  end

  local i = 0
  return function()
            i = i + 1
            return list[i]
         end
end


-- this object contains an array part that holds the parameter objects
local function parse(spec, options, parent)

  local self = setmetatable({
    spec = assert(spec, "spec argument is required"),
    parent = assert(parent, "parent argument is required"),
    options = options,
  }, mt)

  local ok, err = self:validate()
  if not ok then
    return ok, self:log_message(err)
  end

  local new_parameter = require "kong.enterprise_edition.openapi2kong.parameter"
  for _, param_spec in ipairs(self.spec) do
--print(require("pl.pretty").write(param_spec))
    local param_obj, err = new_parameter(param_spec, options, self)
    if not param_obj then
      if err ~= "ignore" then
        return nil, err
      end
    else
      self[#self+1] = param_obj
    end
  end

  ok, err = self:post_validate()
  if not ok then
    return ok, self:log_message(err)
  end

  return self
end

return parse
