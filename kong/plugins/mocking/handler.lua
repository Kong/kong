local cjson       = require("cjson.safe").new()
local lyaml       = require "lyaml"
local gsub        = string.gsub
local match       = string.match
local find        = string.find
local yaml_load   = lyaml.load
local tablex      = require "pl.tablex"

local plugin = {
  VERSION  = "0.1",
  PRIORITY = 1000,
}

local kong = kong
local inspect = require('inspect')

local function _getmethodpath(path, method, accept)

  local rtn

  if method == "GET" then rtn = path.get
  elseif method == "POST" then rtn = path.post
  elseif method == "PUT" then rtn = path.put
  elseif method == "PATCH" then rtn = path.patch
  elseif method == "DELETE" then rtn = path.delete
  elseif method == "OPTIONS" then rtn = path.options
  end

  print(inspect(rtn))

  -- need to improve this
  if rtn and rtn.responses then
    if rtn.responses["200"] then
      print("200")
      if rtn.responses["200"].examples and rtn.responses["200"].examples[accept] then
        return rtn.responses["200"].examples[accept], 200
      else
        return rtn.responses["200"], 200
      end
    elseif rtn.responses["201"] then
      print("201")
      if rtn.responses["201"].examples and rtn.responses["201"].examples[accept] then
        return rtn.responses["201"].examples[accept], 201
      else
        return rtn.responses["201"], 201
      end
    elseif rtn.responses["204"] then
      print("204")
      if rtn.responses["204"].examples and rtn.responses["204"].examples[accept] then
        return rtn.responses["204"].examples[accept], 204
      else
        return rtn.responses["204"], 204
      end
    end
  end

  return nil, 404

end

local function _retrieve_example(parsed_content, uripath, accept, method)

  local paths = parsed_content.paths
  local found = false

  for specpath, value in pairs(paths) do

    --print("spec=",specpath)
    --print("uripath=",uripath)

    local formatted_path = gsub(specpath, "{(.-)}", "[0-9]+")
    local strmatch = match(uripath, formatted_path)
    --print("formated=",formatted_path)
    --print("match=",strmatch)
    if match(uripath, "/%d+") and not match(specpath, "{(.-)}") then
      strmatch = nil
    end
    if strmatch then
      found = true
      local responsepath, status = _getmethodpath(value, method, accept)
      if responsepath then
        kong.response.exit(status, responsepath)
      else
        return kong.response.exit(404, { message = "No examples exist in API specification for  \
          this resource"})
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

  if string.match(conf.api_specification_filename, ".json") then
    local parsed_content = cjson.decode(contents)

    _retrieve_example(parsed_content, uripath, accept, method)


  elseif string.match(conf.api_specification_filename, ".yaml") then

    local parsed_content = yaml_load(contents)

    _retrieve_example(parsed_content, uripath, accept, method)

  else
    kong.response.exit(404, { message = "API Specification file type is not supported" })
  end
end

function plugin:header_filter(conf)
  kong.response.add_header("X-Kong-Mocking-Plugin", "true")
end

return plugin
