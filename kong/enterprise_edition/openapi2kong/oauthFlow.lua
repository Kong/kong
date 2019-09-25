local TYPE_NAME = ({...})[1]:match("kong.enterprise_edition.openapi2kong%.([^%.]+)$")  -- grab type-name from filename

local mt = require("kong.enterprise_edition.openapi2kong.common").create_mt(TYPE_NAME)


function mt:get_trace()
  return self.flow_type
end


function mt:validate()

  if type(self.spec) ~= "table" then
    return nil, ("a %s object expects a table as spec, but got %s"):format(TYPE_NAME, type(self.spec))
  end

  local required_params = {
    implicit = {
      authorizationUrl = "string",
      scopes = "table",
    },
    password = {
      tokenUrl = "string",
      scopes = "table",
    },
    clientCredentials = {
      tokenUrl = "string",
      scopes = "table",
    },
    authorizationCode = {
      authorizationUrl = "string",
      tokenUrl = "string",
      scopes = "table",
    },
  }

  if not required_params[tostring(self.flow_type)] then
    return nil, ("a %s object expects a proper flow_type, but got %s"):format(TYPE_NAME, tostring(self.flow_type))
  end

  for param_name, param_type in pairs(required_params[self.flow_type]) do
    if type(self.spec[param_name]) ~= param_type then
      return nil, ("a %s object expects a %s as %s, but got %s"):format(TYPE_NAME, param_type, param_name, type(self.spec[param_name]))
    end
  end

  if type(self.spec.refreshUrl) ~= "string" and
     type(self.spec.refreshUrl) ~= "nil" then
    return nil, ("a %s object expects a string (or nil) as refreshUrl, but got %s"):format(TYPE_NAME, type(self.spec.refreshUrl))
  end


  return true
end


function mt:post_validate()

  -- do validation after creation

  return true
end


local function parse(flow_type, spec, options, parent)

  local self = setmetatable({
    spec = assert(spec, "spec argument is required"),
    flow_type = assert(flow_type, "flow_type argument is required"),
    parent = assert(parent, "parent argument is required"),
    options = options,
  }, mt)

  local ok, err = self:validate()
  if not ok then
    return ok, self:log_message(err)
  end




  ok, err = self:post_validate()
  if not ok then
    return ok, self:log_message(err)
  end

  return self
end

return parse
