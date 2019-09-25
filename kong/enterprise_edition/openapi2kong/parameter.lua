local TYPE_NAME = ({...})[1]:match("kong.enterprise_edition.openapi2kong%.([^%.]+)$")  -- grab type-name from filename

local mt = require("kong.enterprise_edition.openapi2kong.common").create_mt(TYPE_NAME)


local IN_TYPES = {    -- possible values for the 'in' property and allowed types
  query = { form = true, spaceDelimited = true, pipeDelimited = true, deepObject = true },
  header = { simple = true },
  path = { matrix = true, label = true, simple = true },
  cookie = { form = true },
}

local IGNORE_HEADERS = {  -- header parameters to ignore
  ["accept"] = true,
  ["content-type"] = true,
  ["authorization"] = true,
}


function mt:get_trace()
  if type(self.spec) ~= "nil" and
     type(self.spec) ~= "table" then
      return "<bad spec: " .. type(self.spec) ..">"
  end
  -- Parameter is also used for the Header implementation. In the latter case
  -- there is no `spec.name`, but a `name` property on the object itself
  return self.spec.name or self.name
end


function mt:validate()
  local spec = self.spec

  if type(spec) ~= "table" then
    return nil, ("a %s object expects a table as spec, but got %s"):format(TYPE_NAME, type(spec))
  end

  if type(spec.name) ~= "string" then
    return nil, ("a %s object expects a string as name property, but got %s"):format(TYPE_NAME, type(spec.name))
  end

  if not IN_TYPES[spec["in"] or {}] then
    return nil, ("parameter.in cannot have value '%s'"):format(tostring(spec["in"]))
  end

  if spec["in"] == "header" and IGNORE_HEADERS[spec.name:lower()] then
    return nil, "ignore"
  end

  if spec["in"] == "path" then
    if spec.required ~= true then
      return nil, "parameter.required must be true, if parameter.in == 'path'"
    end
  end

  if spec.schema and spec.content then
    return nil, "parameter cannot have both schema and content properties"

  elseif spec.content then
    -- validate content
    local count = 0
    for media_type, value in pairs(spec.content) do
      count = count + 1
    end
    if count ~= 1 then
      return nil, "parameter.content must have 1 entry, not " ..  count
    end

  elseif not spec.schema then
    return nil, "parameter must have either schema or content property"
  end

  return true
end


-- returns unique id based on properties.
-- A parameter is uniquely identified by the combination of the `in` and `name`
-- properties.
function mt:get_id()
  return self["in"] .. "/" .. self.name
end


function mt:post_validate()

  -- do validation after creation

  return true
end

-- creates a parameter object, if it returns nil+"ignore" the parameter
-- should not be added. Adds properies:
-- self.required (boolean) sanitized and defaulted
-- self.allowEmptyValue (boolean/nil) sanitized and defaulted, nil for non-query types
-- self.allowReserved (boolean/nil) sanitized and defaulted for query+schema, nil otherwise
-- self.style (string/nil) sanitized and defaulted for schema, nil for content
-- self.explode (boolean/nil) sanitized and defaulted for schema, nil for content
-- self.schema (schema object) if schema
-- self.content (array of content/Media Type object) if content/Media Type
-- self.in (useful for derived 'header' objects)
-- self.name (useful for derived 'header' objects, and lowercased for "in == header")
local function parse(spec, options, parent)

  local self = setmetatable({
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
    -- if the error is "ignore" we do not append a log-trace to it
    return ok, err == "ignore" and err or self:log_message(err)
  end

  -- required defaults to false, for path is must be true, but that is part
  -- of validation above
  self.required = self.spec.required
  if type(self.required) ~= "boolean" then
    self.required = false
  end

  -- copying 'in' because derived object 'header' doesn't have it in it's 'spec'
  -- only an artificial injected one during creation
  self["in"] = self.spec["in"]
  -- copy name for the same reason, but for headers lower case it
  self.name = self["in"] == "header" and self.spec.name:lower() or self.spec.name

  if self["in"] == "query" then
    --allowEmptyValue is only for query and defaults to false
    self.allowEmptyValue = type(self.spec.allowEmptyValue) == "boolean" and
                           self.spec.allowEmptyValue or false
  end

  if self.spec.schema then    -- we're based on a schema

    -- style
    self.style = self.spec.style or
                 self["in"] == "query" and "form" or
                 self["in"] == "path" and "simple" or
                 self["in"] == "cookie" and "form" or
                 self["in"] == "header" and "simple"
    if not IN_TYPES[self["in"]][self.style] then
      return nil, self:log_message(("style '%s' is not valid for a '%s' parameter"):format(self.style, self["in"]))
    end

    -- explode
    self.explode = self.spec.explode
    if type(self.explode) ~= "boolean" then
      self.explode = (self.style == "form" and true) or false
    end

    -- allowReserved
    if self["in"] == "query" then
      self.allowReserved = type(self.spec.allowReserved) == "boolean" and
                           self.spec.allowReserved or false
    end

    -- add schema property
    local new_schema = require "kong.enterprise_edition.openapi2kong.schema"
    self.schema, err = new_schema(self.spec.schema, options, self)
    if not self.schema then
      return nil, err
    end

  else    -- we're based on a Media Type (content property)
    local new_mediaType = require "kong.enterprise_edition.openapi2kong.mediaType"
    local contenttype, content_spec = next(self.spec.content) -- only 1 entry
    self.content = {}
    -- despite only 1 entry, we're making it an array, such that it follows the
    -- same structure as the `requestBody` object
    self.content[1], err = new_mediaType(contenttype, content_spec, options, self)
    if not self.content[1] then
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
