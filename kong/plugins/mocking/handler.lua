local cjson       = require("cjson.safe").new()
local lyaml       = require "lyaml"
local gsub        = string.gsub
local match       = string.match
local ngx         = ngx
local random      = math.random
local plugin = {
  VERSION  = "0.1",
  -- Mocking plugin should execute after all other plugins
  PRIORITY = -1,
}

local kong = kong
-- spec version
local isV3 = false
local isV2 = false

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
      if tempindex == string.len(looppath) then
          break
      end
      --Extract and insert the sub string using index of '&'
      table.insert( stringtable, string.sub(looppath, 1,tempindex-1 ))
      looppath = string.sub(looppath,tempindex+1,string.len( looppath ))
  end
  table.insert(stringtable,looppath)
  --kong.log.inspect('paramtable',stringtable)
  return stringtable
end


-- returns a boolean by comparing value of the fields supplied in query params
local function filterexamples(example)
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
      sval = string.sub(dv,string.find( dv,'=' )+1,string.len( dv ))
      --kong.log.inspect('skey.....sval'..skey..'.....'..sval)
      value = find_key(example,skey)
      --kong.log.inspect('value....'..value)
      if(string.upper( sval ) == string.upper( value )) then
        return true
      end
    end
    return false
  end
end



-- Extract example value in V3.0
-- returns lua table with all the values extracted and appended from multiple examples
local function find_example_value(tbl, key)

  local values = {}
  local no_qparams = (kong.request.get_raw_query() == nil or kong.request.get_raw_query() =='')
   for _, lv in pairs(tbl) do
     if type(lv) == "table" then
       for dk, dv in pairs(lv) do
        if dk == key then
          if type(dv) == "table" then
            --We could have empty {} value in example 
            --Go ahead in capture it in table if there are no query params, Filter it if qparams exists
            if (no_qparams and next(dv) == nil) then table.insert( values, dv) end
             for _, v in pairs(dv) do
              -- If the example values are just Key Value pairs go ahead and add them to table
              if(type(v) ~= "table") then
                table.insert( values, dv)
                break
              elseif filterexamples(v) then table.insert( values, v) end
             end
          end
        end
       end
      end
    end
  
  if next(values) == nil then
   -- kong.log.inspect('values....',values)
    return nil
  else
    --kong.log.inspect('values....',values)
    return values
 end
end

local function get_example(accept, tbl)
  if isV2 then
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
    if find_key(tbl, accept) then
      --Removed response object reference as there is no such object within examples hierarchy
      --Removed value :: Not required, referencing object examples in this case will return value
      if find_key(tbl, accept).examples then
       local retval = find_key(tbl, accept).examples
        if find_example_value(retval,"value") then
         return  (find_example_value(retval,"value"))
        end
      -- Single Example use case, Go ahead and use find_key
      elseif find_key(tbl, accept).example then
        local retval = find_key(tbl, accept).example
         if find_key(retval,"value") then
          return  (find_key(retval,"value"))
         end
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
      return get_example(accept, rtn.responses["200"]), 200
    elseif rtn.responses["201"] then
      return get_example(accept, rtn.responses["201"]), 201
    elseif rtn.responses["204"] then
      return get_example(accept, rtn.responses["204"]), 204
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

  -- check spec version
  if result.openapi then
    isV3 = true
    isV2 = false
  else
    isV2 = true
    isV3 = false
  end

  return result
end

local function retrieve_example(parsed_content, uripath, accept, method)
  local paths = parsed_content.paths
  local found = false
  -- Check to make sure we have paths in the spec file, Corrupt or bad spec file
  if (paths) then
  for specpath, value in pairs(paths) do
   
    -- build formatted string for exact match
    local formatted_path = gsub(specpath, "{(.-)}", "[A-Za-z0-9]+") .. "$"
    local strmatch = match(uripath, formatted_path)
    if strmatch then
      found = true
      local responsepath, status = get_method_path(value, method, accept)
      if responsepath then
        kong.response.exit(status, responsepath)
      else
        return kong.response.exit(404, { message = "No examples exist in API specification for this" ..
         " resource with Accept Header (" .. accept .. ")"})
      end
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

  -- grab Accept header which is used to retrieve associated mock response, or default to "application/json"
  local accept = kong.request.get_header("Accept") or kong.request.get_header("accept") or "application/json"
  if accept == "*/*" then accept = "application/json" end
  local method = kong.request.get_method()

  local specfile, err = kong.db.files:select_by_path("specs/" .. conf.api_specification_filename)
  if err or (specfile == nil or specfile == '') then
    return kong.response.exit(404, { message = "API Specification file not found. " ..
     "Check Plugin 'api_specification_filename' (" .. conf.api_specification_filename .. ")" })
  end

  local contents = specfile and specfile.contents or ""

  local parsed_content = load_spec(contents)

  if conf.random_delay then
    ngx.sleep(random(conf.min_delay_time,conf.max_delay_time))
  end
  retrieve_example(parsed_content, uripath, accept, method)

end

function plugin:header_filter(conf)
  kong.response.add_header("X-Kong-Mocking-Plugin", "true")
end

return plugin

