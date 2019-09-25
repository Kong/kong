local TYPE_NAME = ({...})[1]:match("kong.enterprise_edition.openapi2kong%.([^%.]+)$")  -- grab type-name from filename

local new_parameter = require "kong.enterprise_edition.openapi2kong.parameter"

--[[
The header object is a slightly different version from the parameter object
- it MUST NOT have a `name` property
- it MUST NOT have an `in` property

--]]

-- dereference_mt is the metatable initially assigned, just to be able to
-- call the "dereference" method
local dereference_mt = require("kong.enterprise_edition.openapi2kong.common").create_mt(TYPE_NAME)

-- the header_mt is the mt assigned later, and it will get a complete
-- copy of the "parameter" mt, except for "type" being "header".
local header_mt = {}
local header_mt_content_to_be_copied = true


local function parse(name, spec, options, parent)

  if type(spec) ~= "table" then
    return nil, "a header object expects a table as spec, but got " .. type(spec)
  end

  if type(name) ~= "string" then
    return nil, "a header object expects a string as name, but got " .. type(name)
  end

  local temp_header = setmetatable({
    spec = spec,
    name = name,
    parent = assert(parent, "parent argument is required"),
    options = options,
  }, dereference_mt)

  -- we must dereference before calling into "parameter", otherwise "parameter"
  -- does it for us, and then we cannot update the "spec" to the modified copy
  -- we need
  do
    local ok, err = temp_header:dereference()
    if not ok then
      return ok, temp_header:log_message(err)
    end
    -- prevent accidental access to non-dereferenced spec table
    spec = nil -- luacheck: ignore
  end

  assert(temp_header.spec["in"] == nil, "'in' property must not be specified")
  assert(temp_header.spec.name == nil, "'name' property must not be specified")


  -- since we'll be injecting the 'name' and 'in' properties, and we do not
  -- want to modify/touch the original `spec` property we create a (shallow) copy
  local spec_copy = {}
  for k,v in pairs(temp_header.spec) do
    spec_copy[k] = v
  end

  -- inject properties in the copy-spec
  spec_copy.name = name
  spec_copy["in"] = "header"  --TODO: make "in" a property of the parameter object

  -- Create a parmeter object, based on our copy-spec with injected properties
  local param_obj, err = new_parameter(spec_copy, options, parent)
  if not param_obj then
    -- ugly hack to update error messages
    err = err:gsub("[Pp]arameter", TYPE_NAME)

    return param_obj, err  -- this can be "nil+ignore" !!!!
  end

  if header_mt_content_to_be_copied then
    -- the first time we get our hands on a parameter object, so now we have
    -- the opportunity to create the header_mt with all the same methods
    local param_mt = getmetatable(param_obj)
    for k, v in pairs(param_mt) do
      --print("copying: ", k)
      header_mt[k] = v
    end

    -- these properties should be specific to the header object
    header_mt.__index = header_mt
    header_mt.type = TYPE_NAME

    header_mt_content_to_be_copied = false
  end

  -- set the original "spec" tables, instead of the modified copy ones
  param_obj.spec = temp_header.spec
  param_obj.spec_ref = temp_header.spec_ref

  return setmetatable(param_obj, header_mt)
end

return parse
