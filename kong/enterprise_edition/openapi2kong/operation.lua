local TYPE_NAME = ({...})[1]:match("kong.enterprise_edition.openapi2kong%.([^%.]+)$")  -- grab type-name from filename

local mt = require("kong.enterprise_edition.openapi2kong.common").create_mt(TYPE_NAME)


function mt:get_trace()
  return self.method
end


function mt:validate()

  if type(self.method) ~= "string" then
    return nil, ("a %s object expects a string as method, but got %s"):format(TYPE_NAME, type(self.method))
  end

  if type(self.spec) ~= "table" then
    return nil, ("a %s object expects a table as spec, but got %s"):format(TYPE_NAME, type(self.spec))
  end

  if type(self.spec.security) ~= "table" and
     type(self.spec.security) ~= "nil" then
    return nil, ("a %s object expects a table as security property, but got %s"):format(TYPE_NAME, type(self.spec.security))
  end

  return true
end


function mt:post_validate()

  -- do validation after creation

  return true
end


local function parse(method, spec, options, parent)

  local self = setmetatable({
    method = assert(method, "method is required"),
    spec = assert(spec, "spec argument is required"),
    parent = assert(parent, "parent argument is required"),
    options = options,
  }, mt)

  local ok, err = self:validate()
  if not ok then
    return ok, self:log_message(err)
  end

  for _, property in ipairs { "parameters", "requestBody", "servers" } do
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

  if self.spec.security then
    local new_securityRequirements = require("kong.enterprise_edition.openapi2kong.securityRequirements")
    self.security, err = new_securityRequirements(self.spec.security, options, self)
    if not self.security then
      return nil, err
    end
  end

  ok, err = self:post_validate()
  if not ok then
    return ok, self:log_message(err)
  end

  return self
end

return parse
