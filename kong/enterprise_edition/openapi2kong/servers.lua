local new_server = require("kong.enterprise_edition.openapi2kong.server")

local TYPE_NAME = ({...})[1]:match("kong.enterprise_edition.openapi2kong%.([^%.]+)$")  -- grab type-name from filename

local mt = require("kong.enterprise_edition.openapi2kong.common").create_mt(TYPE_NAME)


function mt:get_trace()
  return ""
end


function mt:validate()

  if type(self.spec) ~= "table" then
    return nil, ("a %s object expects a table, but got %s"):format(TYPE_NAME, type(self.spec))
  end

  -- do validation

  return true
end


function mt:post_validate()

  -- check equality: only host or port may differ
  local function eq(t1, t2)
    for k,v in pairs(t1) do
      if k ~= "host" and k ~= "port" then
        if v ~= t2[k] then
          return false
        end
      end
    end
    for k,v in pairs(t2) do
      if k ~= "host" and k ~= "port" then
        if v ~= t1[k] then
          return false
        end
      end
    end
    return true
  end

  for i = 2, #self do
    if not eq(self[1].parsed_url, self[i].parsed_url) then
      return nil, "server urls should not differ other than host or port"
    end
  end

  return true
end

-- The returned object is itself an array (numerical part of the table)
-- holding all the `server` objects
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

  for i, server in ipairs(spec) do
    local err
    self[i], err = new_server(server, options, self)
    if not self[i] then
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
