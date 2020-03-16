local cjson = require("cjson.safe").new()
local singletons   = require "kong.singletons"
local pl_stringx = require "pl.stringx"
local pl_tablex = require "pl.tablex"
local lyaml      = require "lyaml"
local yaml_load = lyaml.load
local inspect = require "inspect"
--local route = require "kong.plugins.mocking.route".new()

--assert(ngx.get_phase() == "timer", "The world is coming to an end!")
local plugin = {
  VERSION  = "0.1",
  PRIORITY = 1000,
}

local kong = kong
local ngx = ngx
--local services  = kong.db.services
local time = ngx.time
local inspect = require('inspect')

local function getmethodpath(path, method)
  if method == "GET" then return path.get
  elseif method == "POST" then return path.post
  elseif method == "PUT" then return path.put
  elseif method == "PATCH" then return path.patch
  elseif method == "DELETE" then return path.delete
  elseif method == "HEAD" then return path.head
  elseif method == "CONNECT" then return path.connect
  elseif method == "TRACE" then return path.trace
  end

end

function plugin:access(plugin_conf)

  --kong.log("\027[31m\n",inspect(plugin_conf), "\027[0m")

  local service_id = plugin_conf.service_id

  local service = kong.db.services:select({ id = service_id })

  --kong.log("service=", inspect(service))

  --kong.log(inspect(kong.request))

  --print("accept=", kong.request.get_header("accept"))
  --print("method=", kong.request.get_method())

  -- Get resource information
  local uripath = kong.request.get_path()
  local accept = kong.request.get_header("Accept") or kong.request.get_header("accept")
  local method = kong.request.get_method()

  --print("path", path)

  local specfile, err = singletons.db.files:select_by_path("specs/" .. plugin_conf.api_specification_filename)

  if err then
    return kong.response.exit(404, { message = "API Specification file not found. Check Plugin 'api_specification_filename' value" })
  end

  local contents = specfile and specfile.contents or ""

  --print(contents)

  if string.match(plugin_conf.api_specification_filename, ".json") then
    --print("specfile=",plugin_conf.api_specification_filename)
    local parsed_content = cjson.decode(contents)
    --print("parsed=",inspect(parsed_content))
    
    local paths = parsed_content.paths
    --print("paths=",inspect(paths))
    -- hard coded for demo
    local path = paths["/Patient/{id}"]

    if not path then
      return kong.response.exit(404, { message = "Path does not exist in API Specification" })
    end
       --local path = paths[0] or paths[1]
  
    --print("path=", inspect(path))

    local responsepath = getmethodpath(path, method)
    --print("responsepath", inspect(responsepath))
    local examplejson = responsepath.responses["200"].examples["application/json+fhir"]
  
    return kong.response.exit(200, examplejson)

  else

    local parsed_content = yaml_load(contents)

    local paths = parsed_content.paths
  
    --print("islist====", lua_helpers.is_list(paths))
  
    local path = paths[uripath]
  
  
    -- hack!! need to understand how to search yaml_load
    --if string.match(uripath, "users") then
    --  path = paths["/users/{id}"]
    --end
  
    if not path then
      return kong.response.exit(404, { message = "Path does not exist in API Specification" })
    end
  
    local responsepath = getmethodpath(path, method)
    --kong.log("responsepath", inspect(responsepath))
    local examplejson = responsepath.responses["200"].examples["application/json"]
  
    return kong.response.exit(200, examplejson)
  end

end --]]


---[[ runs in the 'header_filter_by_lua_block'
  function plugin:header_filter(plugin_conf)

    kong.response.add_header("X-Kong-Mocking-Plugin", "true")


    end --]]


---[[ runs in the 'body_filter_by_lua_block'
  function plugin:body_filter(plugin_conf)




  end --]]




-- return our plugin object
      return plugin
