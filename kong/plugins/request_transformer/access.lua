local utils = require "kong.tools.utils"
local stringy = require "stringy"
local Multipart = require "multipart"

local _M = {}

local CONTENT_LENGTH = "content-length"
local FORM_URLENCODED = "application/x-www-form-urlencoded"
local MULTIPART_DATA = "multipart/form-data"
local CONTENT_TYPE = "content-type"

local function iterate_and_exec(val, cb)
  if utils.table_size(val) > 0 then
    for _, entry in ipairs(val) do
      local parts = stringy.split(entry, ":")
      cb(parts[1], utils.table_size(parts) == 2 and parts[2] or nil)
    end
  end
end

local function get_content_type()
  local header_value = ngx.req.get_headers()[CONTENT_TYPE]
  if header_value then
    return stringy.strip(header_value):lower()
  end
end

function _M.execute(conf)
  if not conf then return end

  if conf.add then

    -- Add headers
    if conf.add.headers then
      iterate_and_exec(conf.add.headers, function(name, value)
        ngx.req.set_header(name, value)
      end)
    end

    -- Add Querystring
    if conf.add.querystring then
      local querystring = ngx.req.get_uri_args()
      iterate_and_exec(conf.add.querystring, function(name, value)
        querystring[name] = value
      end)
      ngx.req.set_uri_args(querystring)
    end

    if conf.add.form then
      local content_type = get_content_type()
      if content_type and stringy.startswith(content_type, FORM_URLENCODED) then
        -- Call ngx.req.read_body to read the request body first
        ngx.req.read_body()

        local parameters = ngx.req.get_post_args()
        iterate_and_exec(conf.add.form, function(name, value)
          parameters[name] = value
        end)
        local encoded_args = ngx.encode_args(parameters)
        ngx.req.set_header(CONTENT_LENGTH, string.len(encoded_args))
        ngx.req.set_body_data(encoded_args)
      elseif content_type and stringy.startswith(content_type, MULTIPART_DATA) then
        -- Call ngx.req.read_body to read the request body first
        ngx.req.read_body()

        local body = ngx.req.get_body_data()
        local parameters = Multipart(body and body or "", content_type)
        iterate_and_exec(conf.add.form, function(name, value)
          parameters:set_simple(name, value)
        end)
        local new_data = parameters:tostring()
        ngx.req.set_header(CONTENT_LENGTH, string.len(new_data))
        ngx.req.set_body_data(new_data)
      end
    end

  end

  if conf.remove then

    -- Remove headers
    if conf.remove.headers then
      iterate_and_exec(conf.remove.headers, function(name, value)
        ngx.req.clear_header(name)
      end)
    end

    if conf.remove.querystring then
      local querystring = ngx.req.get_uri_args()
      iterate_and_exec(conf.remove.querystring, function(name)
        querystring[name] = nil
      end)
      ngx.req.set_uri_args(querystring)
    end

    if conf.remove.form then
      local content_type = get_content_type()
      if content_type and stringy.startswith(content_type, FORM_URLENCODED) then
        local parameters = ngx.req.get_post_args()

        iterate_and_exec(conf.remove.form, function(name)
          parameters[name] = nil
        end)

        local encoded_args = ngx.encode_args(parameters)
        ngx.req.set_header(CONTENT_LENGTH, string.len(encoded_args))
        ngx.req.set_body_data(encoded_args)
      elseif content_type and stringy.startswith(content_type, MULTIPART_DATA) then
        -- Call ngx.req.read_body to read the request body first
        ngx.req.read_body()

        local body = ngx.req.get_body_data()
        local parameters = Multipart(body and body or "", content_type)
        iterate_and_exec(conf.remove.form, function(name)
          parameters:delete(name)
        end)
        local new_data = parameters:tostring()
        ngx.req.set_header(CONTENT_LENGTH, string.len(new_data))
        ngx.req.set_body_data(new_data)
      end
    end

  end

end

return _M
