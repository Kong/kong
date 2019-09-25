local new_encoding = require("kong.enterprise_edition.openapi2kong.encoding")

local TYPE_NAME = ({...})[1]:match("kong.enterprise_edition.openapi2kong%.([^%.]+)$")  -- grab type-name from filename


local mt = require("kong.enterprise_edition.openapi2kong.common").create_mt(TYPE_NAME)


function mt:get_trace()
  return ""
end


function mt:validate()

  if type(self.spec) ~= "table" then
    return nil, ("a %s object expects a table, but got %s"):format(TYPE_NAME, type(self.spec))
  end

  return true
end


function mt:post_validate()

  -- do validation after creation

  return true
end


-- returns an array with encoding entries
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

  self.encodings = {}
  for property_name, encoding_spec in pairs(spec) do
    local encoding_obj, err = new_encoding(property_name, encoding_spec, options, self)
    if not encoding_obj then
      return nil, err
    end
    self.encodings[#self.encodings+1] = encoding_obj
  end

  ok, err = self:post_validate()
  if not ok then
    return ok, self:log_message(err)
  end

  return self
end

return parse
