local stringy = require "stringy"
local Multipart = require "multipart"

local _M = {}

local CONTENT_LENGTH = "content-length"
local FORM_URLENCODED = "application/x-www-form-urlencoded"
local MULTIPART_DATA = "multipart/form-data"
local CONTENT_TYPE = "content-type"

local function retrieve_params(val)
  local t = {}
  if utils.table_size(val) > 0 then
    for _, entry in ipairs(val) do
      local parts = stringy.split(entry, ":")
      t[parts[1]] = parts[2]
    end
  end
  return t
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
      if not querystring or utils.table_size(querystring) == 0 then 
        querystring = {} 
      end

      local new_params = retrieve_params(conf.add.querystring)
      for k,v in pairs(new_params) do
        querystring[k] = v
      end

      ngx.req.set_uri_args(querystring)
    end

    if conf.add.form then
      local content_type = stringy.strip(string.lower(request.get_headers()[CONTENT_TYPE]))
      if utils.starts_with(content_type, FORM_URLENCODED) then
        -- Call ngx.req.read_body to read the request body first
        -- or turn on the lua_need_request_body directive to avoid errors.
        ngx.req.read_body()

        local parameters = ngx.req.get_post_args()
        iterate_and_exec(conf.add.form, function(name, value)
          parameters[name] = value
        end)
        local encoded_args = ngx.encode_args(parameters)
        ngx.req.set_header(CONTENT_LENGTH, string.len(encoded_args))
        ngx.req.set_body_data(encoded_args)
      elseif utils.starts_with(content_type, MULTIPART_DATA) then
        -- Call ngx.req.read_body to read the request body first
        -- or turn on the lua_need_request_body directive to avoid errors.
        ngx.req.read_body()

        local body = ngx.req.get_body_data()
        local parameters = Multipart(body, content_type)
        iterate_and_exec(conf.add.form, function(name, value)
          parameters:set_simple(name, value)
        end)
        local new_data = parameters:tostring()
        ngx.req.set_header(CONTENT_LENGTH, string.len(new_data))
        ngx.req.set_body_data(new_data)
      end
      
    end

  elseif conf.remove then

  end

end

return _M
