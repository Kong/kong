local utils = require "kong.tools.utils"
local stringy = require "stringy"
local cjson = require "cjson"

local _M = {}

local APPLICATION_JSON = "application/json"
local CONTENT_TYPE = "content-type"

local function get_content_type()
  local header_value = ngx.header[CONTENT_TYPE]
  if header_value then
    return stringy.strip(header_value):lower()
  end
  return nil
end

local function read_response_body()
  local chunk, eof = ngx.arg[1], ngx.arg[2] 
  local buffered = ngx.ctx.buffered 
  if not buffered then 
    buffered = {}
    ngx.ctx.buffered = buffered 
  end
  if chunk ~= "" then 
    buffered[#buffered + 1] = chunk 
    ngx.arg[1] = nil 
  end
  if eof then 
    local response_body = table.concat(buffered) 
    return response_body
  end
  return nil
end

local function read_json_body()
  local body = read_response_body()
  if body then
    local status, res = pcall(cjson.decode, body)
    if status then
      return res
    end
  end
  return nil
end

local function set_json_body(json)
  local body = cjson.encode(json)
  ngx.arg[1] = body
end

local function iterate_and_exec(val, cb)
  if utils.table_size(val) > 0 then
    for _, entry in ipairs(val) do
      local parts = stringy.split(entry, ":")
      cb(parts[1], utils.table_size(parts) == 2 and parts[2] or nil)
    end
  end
end

function _M.execute(conf)
  if not conf then return end

  local is_json_body = get_content_type() == APPLICATION_JSON

  if ((conf.add and conf.add.json) or (conf.remove and conf.remove.json)) and is_json_body then
    local json_body = read_json_body()
    if json_body then

      if conf.add and conf.add.json then
        iterate_and_exec(conf.add.json, function(name, value)
          local v = cjson.encode(value)
          if stringy.startswith(v, "\"") and stringy.endswith(v, "\"") then
            v = v:sub(2, v:len() - 1):gsub("\\\"", "\"") -- To prevent having double encoded quotes
          end
          json_body[name] = v
        end)
      end

      if conf.remove and conf.remove.json then
        iterate_and_exec(conf.remove.json, function(name)
          json_body[name] = nil
        end)
      end

      set_json_body(json_body) 
    end
  end

end

return _M
