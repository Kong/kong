local TYPE_NAME = ({...})[1]:match("kong.enterprise_edition.openapi2kong%.([^%.]+)$")  -- grab type-name from filename

local mt = require("kong.enterprise_edition.openapi2kong.common").create_mt(TYPE_NAME)


function mt:get_trace()
  return self.scheme_name
end


function mt:validate()

  if type(self.spec) ~= "table" then
    return nil, ("a %s object expects a table as spec, but got %s"):format(TYPE_NAME, type(self.spec))
  end

  if type(self.scheme_name) ~= "string" then
    return nil, ("a %s object expects a string as scheme_name, but got %s"):format(TYPE_NAME, type(self.scheme_name))
  end

  if type(self.scopes) ~= "table" then
    return nil, ("a %s object expects a table as scopes, but got %s"):format(TYPE_NAME, type(self.scopes))
  end

  local spec = self.spec
  if spec.type == "apiKey" then
    if type(spec.name) ~= "string" then
      return nil, ("a %s object of type %s expects a string as name property, but got %s"):format(TYPE_NAME, spec.type, type(spec.name))
    end

    if not ({ query = 1,
              header = 2,
              cookie = 3})[tostring(spec["in"])] then
      return nil, ("a %s object of type %s expects a proper in property, but got %s"):format(TYPE_NAME, spec.type, tostring(spec["in"]))
    end

  elseif spec.type == "http" then
    if type(spec.scheme) ~= "string" then
      return nil, ("a %s object of type %s expects a string as scheme property, but got %s"):format(TYPE_NAME, spec.type, type(spec.scheme))
    end

  elseif spec.type == "oauth2" then
    if type(spec.flows) ~= "table" then
      return nil, ("a %s object of type %s expects a table as flows property, but got %s"):format(TYPE_NAME, spec.type, type(spec.flows))
    end
    if not next(spec.flows) then
      return nil, ("a %s object of type %s expects at least 1 entry in the flows property"):format(TYPE_NAME, spec.type)
    end

  elseif spec.type == "openIdConnect" then
    if type(spec.openIdConnectUrl) ~= "string" then
      return nil, ("a %s object of type %s expects a string as openIdConnectUrl property, but got %s"):format(TYPE_NAME, spec.type, type(spec.openIdConnectUrl))
    end

  else
    return nil, ("a %s object expects a valid type property, but got %s"):format(TYPE_NAME, tostring(spec.type))
  end

  return true
end


function mt:post_validate()

  -- do validation after creation

  return true
end


-- equality can usually be determined by comparing the "spec" properties; same
-- table is same resulting object. But in this case there are 2 spec entries
-- to be compared; the securityScheme spec, and the scopes table, which is
-- comming in from the underlying securityRequirements object
local function parse(scheme_name, scopes, spec, options, parent)

  local self = setmetatable({
    spec = assert(spec, "spec argument is required"),
    scheme_name = assert(scheme_name, "scheme_name argument is required"),
    scopes = assert(scopes, "scopes argument is required"),
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

  if self.spec.type == "oauth2" then
    local new_flow = require("kong.enterprise_edition.openapi2kong.oauthFlow")
    self.flows = {}
    for flow_type, flow_spec in pairs(self.spec.flows) do
      local flow_obj, err = new_flow(flow_type, flow_spec, options, self)
      if not flow_obj then
        return nil, err
      end
      self.flows[#self.flows+1] = flow_obj
    end
  end


  ok, err = self:post_validate()
  if not ok then
    return ok, self:log_message(err)
  end

  return self
end

return parse
