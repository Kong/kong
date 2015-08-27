local utils = require "kong.tools.utils"
local stringy = require "stringy"

local _M = {}

local APPLICATION_JSON = "application/json"
local CONTENT_TYPE = "content-type"
local CONTENT_LENGTH = "content-length"

local function get_content_type()
  local header_value = ngx.header[CONTENT_TYPE]
  if header_value then
    return stringy.strip(header_value):lower()
  end
  return nil
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
  local is_json_body = get_content_type() == APPLICATION_JSON

  if conf.add then

    -- Add headers
    if conf.add.headers then
      iterate_and_exec(conf.add.headers, function(name, value)
        ngx.header[name] = value
      end)
    end

    -- Removing the header because the body is going to change
    if conf.add.json and is_json_body then
      ngx.header[CONTENT_LENGTH] = nil
    end

  end

  if conf.remove then

    -- Remove headers
    if conf.remove.headers then
      iterate_and_exec(conf.remove.headers, function(name, value)
        ngx.header[name] = nil
      end)
    end

    -- Removing the header because the body is going to change
    if conf.remove.json and is_json_body then
      ngx.header[CONTENT_LENGTH] = nil
    end

  end

end

return _M
