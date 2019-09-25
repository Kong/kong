
local TYPE_NAME = ({...})[1]:match("kong.enterprise_edition.openapi2kong%.([^%.]+)$")  -- grab type-name from filename
local url = require "socket.url"


local mt = require("kong.enterprise_edition.openapi2kong.common").create_mt(TYPE_NAME)


function mt:get_trace()
  if type(self.spec) ~= "nil" and
     type(self.spec) ~= "table" then
      return "<bad spec: " .. type(self.spec) ..">"
  end
  return self.spec.url
end


function mt:validate()

  if type(self.spec) ~= "table" then
    return nil, ("a %s object expects a table, but got %s"):format(TYPE_NAME, type(self.spec))
  end

  if type(self.spec.url) ~= "string" then
    return nil, ("a %s object expects a string as url property, but got %s"):format(TYPE_NAME, type(self.spec.url))
  end

  return true
end


function mt:post_validate()

  -- do validation after creation

  return true
end


-- Object returned has a single property: `parsed_url` being the url table
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

  local server_url = spec.url:gsub("{(.-)}", function(param_name)
      local default_value = ((spec.variables or {})[param_name] or{}).default
      if not default_value then
        error(("no default value defined for '%s' in server '%s'"):format(param_name, spec.url))
      end
      return default_value
    end)

  self.parsed_url, err = url.parse(server_url)
  if not self.parsed_url then
    return nil, self:log_message(err)
  end

  self.parsed_url.authority = nil -- drop because it also contains the port
  self.parsed_url.port = self.parsed_url.port or
                         self.parsed_url.scheme == "http" and "80" or
                         self.parsed_url.scheme == "https" and "443" or
                         nil

  ok, err = self:post_validate()
  if not ok then
    return ok, self:log_message(err)
  end

  return self
end


return parse
