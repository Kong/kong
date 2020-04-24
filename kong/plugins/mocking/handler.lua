local cjson       = require("cjson.safe").new()
local lyaml       = require "lyaml"
local gsub        = string.gsub
local match       = string.match
local find        = string.find
local tablex      = require "pl.tablex"

local plugin = {
  VERSION  = "0.1",
  PRIORITY = 1000,
}

local kong = kong
local inspect = require('inspect')

local function find_key(tbl, key)

  for lk, lv in pairs(tbl) do
    if lk == key then return lv end
    if type(lv) == "table" then
      for dk, dv in pairs(lv) do
        if dk == key then return dk end
        if type(dv) == "table" then
          for ek, ev in pairs(dv) do

            if ek == key then return ev end
          end
        end
      end
    end
  end

  return nil
end

local function get_example(accept, tbl)
  if find_key(tbl, "examples") then
    if find_key(tbl, "examples")[accept] then
      return find_key(tbl, "examples")[accept]
    else
      return find_key(tbl, "examples")
    end
  elseif find_key(tbl, "example") then
    if find_key(tbl, "example")[accept] then
      return find_key(tbl, "example")[accept]
    else
      return find_key(tbl, "example")
    end
  else
    return ""
  end
end

local function get_method_path(path, method, accept)

  local rtn

  if method == "GET" then rtn = path.get
  elseif method == "POST" then rtn = path.post
  elseif method == "PUT" then rtn = path.put
  elseif method == "PATCH" then rtn = path.patch
  elseif method == "DELETE" then rtn = path.delete
  elseif method == "OPTIONS" then rtn = path.options
  end

  -- need to improve this
  if rtn and rtn.responses then
    if rtn.responses["200"] then
      return get_example(accept, rtn.responses["200"]), 200
    elseif rtn.responses["201"] then
      if rtn.responses["201"].examples and rtn.responses["201"].examples[accept] then
        return rtn.responses["201"].examples[accept], 201
      else
        return rtn.responses["201"], 201
      end
    elseif rtn.responses["204"] then
      if rtn.responses["204"].examples and rtn.responses["204"].examples[accept] then
        return rtn.responses["204"].examples[accept], 204
      else
        return rtn.responses["204"], 204
      end
    end
  end

  return nil, 404

end

--- Loads a spec string.
-- Tries to first read it as json, and if failed as yaml.
-- @param spec_str (string) the string to load
-- @return table or nil+err
local function load_spec(spec_str)

  -- first try to parse as JSON
  local result, cjson_err = cjson.decode(spec_str)
  if type(result) ~= "table" then
    -- if fail, try as YAML
    local ok
    ok, result = pcall(lyaml.load, spec_str)
    if not ok or type(result) ~= "table" then
      return nil, ("Spec is neither valid json ('%s') nor valid yaml ('%s')"):
                  format(tostring(cjson_err), tostring(result))
    end
  end

  return result
end

local function retrieve_example(parsed_content, uripath, accept, method)

  local paths = parsed_content.paths
  local found = false

  for specpath, value in pairs(paths) do

    --print("spec=",specpath)
    --print("uripath=",uripath)

    -- build formatted string for exact match
    local formatted_path = "^" .. gsub(specpath, "{(.-)}", "[0-9]+") .. "$"
    local strmatch = match(uripath, formatted_path)
    --print("formated=",formatted_path)
    --print("match=",strmatch)
    if strmatch then
      found = true
      local responsepath, status = get_method_path(value, method, accept)
      if responsepath then
        kong.response.exit(status, responsepath)
      else
        return kong.response.exit(404, { message = "No examples exist in API specification for this resource"})
      end
    end
  end

  if not found then
    return kong.response.exit(404, { message = "Path does not exist in API Specification" })
  end

end

function plugin:access(conf)

  -- Get resource information
  local uripath = kong.request.get_path()
  local accept = kong.request.get_header("Accept") or kong.request.get_header("accept")
  local method = kong.request.get_method()

  local specfile, err = kong.db.files:select_by_path("specs/" .. conf.api_specification_filename)

  if err or (specfile == nil or specfile == '') then
    return kong.response.exit(404, { message = "API Specification file not found. Check Plugin 'api_specification_filename' value" })
  end

  local contents = specfile and specfile.contents or ""

  local parsed_content = load_spec(contents)

  retrieve_example(parsed_content, uripath, accept, method)

end

function plugin:header_filter(conf)
  kong.response.add_header("X-Kong-Mocking-Plugin", "true")
end

return plugin

