local TYPE_NAME = ({...})[1]:match("kong.enterprise_edition.openapi2kong%.([^%.]+)$")  -- grab type-name from filename

local mt = require("kong.enterprise_edition.openapi2kong.common").create_mt(TYPE_NAME)


function mt:get_trace()
  return self.mediatype
end


function mt:validate()

  if type(self.mediatype) ~= "string" then
    return nil, ("a %s object expects a string as mediatype, but got %s"):format(TYPE_NAME, type(self.mediatype))
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


local function parse(mediatype, spec, options, parent)

  local self = setmetatable({
    spec = assert(spec, "spec argument is required"),
    mediatype = assert(mediatype, "mediatype argument is required"),
    parent = assert(parent, "parent argument is required"),
    options = options,
  }, mt)

  local ok, err = self:validate()
  if not ok then
    return ok, self:log_message(err)
  end

  if self.spec.schema then
    local new_schema = require "kong.enterprise_edition.openapi2kong.schema"
    self.schema, err = new_schema(self.spec.schema, options, self)
    if not self.schema then
      return nil, err
    end
  end

  if self.spec.encoding then
    local new_encodings = require "kong.enterprise_edition.openapi2kong.encodings"
    self.encoding, err = new_encodings(self.spec.encoding, options, self)
    if not self.encoding then
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
