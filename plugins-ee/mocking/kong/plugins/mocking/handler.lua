-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson = require("cjson.safe").new()
local lyaml = require "lyaml"
local gsub = string.gsub
local match = string.match
local random = math.random
local meta = require "kong.meta"
local utils = require "kong.tools.utils"

local ngx = ngx
local kong = kong


local MockingHandler = {}

MockingHandler.VERSION = meta.core_version
MockingHandler.PRIORITY = -1 -- Mocking plugin should execute after all other plugins


local function find_key(tbl, key)

  for lk, lv in pairs(tbl) do
    if lk == key then return lv end
    if type(lv) == "table" then
      for dk, dv in pairs(lv) do
        if dk == key then return dv end
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

-- Tokenize the string with '&' and return a table holding all the query params
local function extractParameters(looppath)
  local tempindex
  local stringtable={}

  while(string.find( looppath,'&'))
  do
      tempindex =string.find( looppath,'&')
      --only one query param, Break the iteration and insert value in table
      if tempindex == #looppath then
          break
      end
      --Extract and insert the sub string using index of '&'
      table.insert( stringtable, string.sub(looppath, 1,tempindex-1 ))
      looppath = string.sub(looppath,tempindex+1,#looppath)
  end
  table.insert(stringtable,looppath)
  --kong.log.inspect('paramtable',stringtable)
  return stringtable
end


-- returns a boolean by comparing value of the fields supplied in query params
local function filterexamples(example, qparameters)
  local value
  local skey
  local sval

  local qparams = kong.request.get_raw_query()
  -- Return true when there are no query params. This will ensure no filtering on examples.
  if qparams == nil or qparams =='' then
    return true
  end
  local params = extractParameters(qparams)

  -- Filter empty response when there is/are query params
  if  next(example) == nil then
    return false

  -- Loop through the extracted query params and do a case insensitive comparison of field values within examples
  -- Return true if matched, false if not found
  else
    for _,dv in pairs(params) do
      skey = string.sub( dv,1,string.find( dv,'=' )-1 )
      sval = string.sub(dv,string.find( dv,'=' )+1,#dv)
      --kong.log.inspect('skey.....sval'..skey..'.....'..sval)
      -- Query parameters might be supplied with fields not present in examples i.e value could be nil
      -- In a real world api design, A query parameter might only be used in api business logic and might not be returned in response

      value = find_key(example,skey)
      --kong.log.inspect('value....'..value)

      if value == nil and qparameters then
        if #qparameters > 1 then
          for dk,dv in pairs(qparameters) do
            if string.find(find_key(qparameters,"in"),'query') then
              if string.find(find_key(qparameters,"name"),skey) then return true end
            end
          end
        else
          if string.find(find_key(qparameters,"in"),'query') then
            if string.upper(skey) == string.upper(find_key(qparameters,"name")) then  return true end
          end
        end
      end

      if (value and string.upper( sval ) == string.upper( value )) then
        return true
      end
    end
    return false
  end
end



-- Extract example value in V3.0
-- returns lua table with all the values extracted and appended from multiple examples
local function find_example_value(tbl, key, queryparams)

  local values = {}
  local no_qparams = (kong.request.get_raw_query() == nil or kong.request.get_raw_query() =='')
   for _, lv in pairs(tbl) do
     if type(lv) == "table" then

       for dk, dv in pairs(lv) do
        if dk == key then
          if no_qparams then table.insert( values, dv)
          elseif filterexamples(dv,queryparams) then table.insert( values, dv) end
        end
       end
      end
    end

  if next(values) == nil then
    return nil
  elseif #values == 1 then
    return values[1]
  else
    return values
  end
end


local function get_example(accept, tbl, parameters)
  if kong.ctx.plugin.spec_version == "v2" then
    if find_key(tbl, "examples") then
      if find_key(tbl, "examples")[accept] then
        return find_key(tbl, "examples")[accept]
      end
    elseif find_key(tbl, "example") then
      if find_key(tbl, "example")[accept] then
        return find_key(tbl, "example")[accept]
      end
    else
      return ""
    end
  else
    tbl = tbl.content
    if type(tbl) ~= "table" then
      return ""
    end
    if find_key(tbl, accept) then
      --Removed response object reference as there is no such object within examples hierarchy
      --Removed value :: Not required, referencing object examples in this case will return value
      if find_key(tbl, accept).examples then
       local retval = find_key(tbl, accept).examples
        if find_example_value(retval,"value",parameters) then
         return  (find_example_value(retval,"value",parameters))
        end
      -- Single Example use case, Go ahead and use find_key
      elseif find_key(tbl, accept).example then
        return find_key(tbl, accept).example
      elseif find_key(tbl, accept).schema then
        local retval = find_key(tbl, accept).schema
        if find_key(retval, "example") then
          return find_key(retval, "example")
        end
      else
        return ""
      end
    end
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
      return get_example(accept, rtn.responses["200"], rtn.parameters), 200
    elseif rtn.responses["201"] then
      return get_example(accept, rtn.responses["201"], rtn.parameters), 201
    elseif rtn.responses["204"] then
      return get_example(accept, rtn.responses["204"], rtn.parameters), 204
    end
  end

  return nil, 404
end

--- Loads a spec string.
-- Tries to first read it as json, and if failed as yaml.
-- @param spec_str (string) the string to load
-- @return table or nil+err
local function load_spec(spec_str)
  kong.log.debug("api specification content: ", spec_str)

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

  -- check spec version
  if result.openapi then
    kong.ctx.plugin.spec_version = "v3"
  else
    kong.ctx.plugin.spec_version = "v2"
  end

  return result
end

local function retrieve_example(parsed_content, uripath, accept, method)
  local mocking_response = {}
  local paths = parsed_content.paths
  -- Check to make sure we have paths in the spec file, Corrupt or bad spec file
  if paths then
    for specpath, value in pairs(paths) do
      -- build formatted string for exact match
      local formatted_path = gsub(specpath, "[-.]", "%%%1")
      formatted_path = gsub(formatted_path, "{(.-)}", "[A-Za-z0-9]+") .. "$"
      local strmatch = match(uripath, formatted_path)
      if strmatch then
        local examples, status = get_method_path(value, method, accept)
        if examples and examples ~= ngx.null then
          mocking_response.http_status = status
          mocking_response.examples = examples
          return mocking_response, nil
        else
          mocking_response.http_status = 404
          mocking_response.body = { message = "No examples exist in API specification for this resource with Accept Header (" .. accept .. ")" }
          return mocking_response, nil
        end
      end
    end
  end

  mocking_response.http_status = 404
  mocking_response.body = { message = "Path does not exist in API Specification" }
  return mocking_response, nil
end

function MockingHandler:access(conf)
  -- Get resource information
  local uripath = kong.request.get_path()

  -- grab Accept header which is used to retrieve associated mock response, or default to "application/json"
  local accept = kong.request.get_header("Accept") or kong.request.get_header("accept") or "application/json"
  if accept == "*/*" then accept = "application/json" end
  local method = kong.request.get_method()

  local contents
  if conf.api_specification == nil or conf.api_specification == '' then
    if kong.db == nil then
      return kong.response.exit(404, { message = "API Specification file api_specification_filename defined which is not supported in dbless mode - not supported. Use api_specification instead" })
    end

    local specfile, err = kong.db.files:select_by_path("specs/" .. conf.api_specification_filename)

    if err or (specfile == nil or specfile == '') then
      return kong.response.exit(404, { message = "API Specification file not found. " ..
       "Check Plugin 'api_specification_filename' (" .. conf.api_specification_filename ")" })
    end

    contents = specfile and specfile.contents or ""

  else

    contents = conf.api_specification

  end

  local parsed_content, err = load_spec(contents)
  if err then
    kong.log.err("failed to load spec content")
    kong.response.exit(400, { message = err })
  end

  local result, err = retrieve_example(parsed_content, uripath, accept, method)
  if not result then
    return kong.response.exit(500, err)
  end

  if conf.random_examples then
    if utils.is_array(result.examples) then
      result.examples = result.examples[random(1, #result.examples)]
    else
      kong.log.warn("Could not randomly select an example. Table expected but got " .. type(result.examples))
    end
  end

  result.body = result.body or result.examples

  if conf.random_delay then
    ngx.sleep(random(conf.min_delay_time,conf.max_delay_time))
  end

  return kong.response.exit(result.http_status, result.body)
end

function MockingHandler:header_filter(conf)
  kong.response.add_header("X-Kong-Mocking-Plugin", "true")
end

return MockingHandler
