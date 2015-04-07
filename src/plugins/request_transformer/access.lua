local stringy = require "stringy"

local _M = {}

local function iterate_and_exec(val, cb)
  for _, entry in ipairs(val) do
    local parts = stringy.split(entry, ":")
    cb(parts[0], parts[1])  
  end
end

--[[
local function escape_regex(x)
  return (x:gsub('%%', '%%%%')
           :gsub('%^', '%%%^')
           :gsub('%$', '%%%$')
           :gsub('%(', '%%%(')
           :gsub('%)', '%%%)')
           :gsub('%.', '%%%.')
           :gsub('%[', '%%%[')
           :gsub('%]', '%%%]')
           :gsub('%*', '%%%*')
           :gsub('%+', '%%%+')
           :gsub('%-', '%%%-')
           :gsub('%?', '%%%?'))
end
--]]

function _M.execute(conf)
  if not conf then return end

  -- Headers
  if conf.headers and utils.table_size(conf.headers) > 0 then
    iterate_and_exec(conf.headers, function(name, value)
      ngx.req.set_header(name, value)
    end)
  end

  -- Querystring
  if conf.querystring and utils.table_size(conf.querystring) > 0 then
    local querystring = ngx.req.get_uri_args()
    iterate_and_exec(conf.querystring, function(name, value)
      querystring[name] = value
    end)
    ngx.req.set_uri_args(querystring)
  end

  -- Form
  if conf.form and utils.table_size(conf.form) > 0 then
    -- Call ngx.req.read_body to read the request body first
    -- or turn on the lua_need_request_body directive to avoid errors.

    ngx.req.read_body()
    local parameters = ngx.req.get_post_args()
    iterate_and_exec(conf.form, function(name, value)
      parameters[name] = value
    end)

    ngx.req.set_header("content-length", string.len(parameters))
    ngx.req.set_body_data(parameters)
  end

-- MULTIPART
--[[
        local data = request.get_body_data()
        if not data then data = "" end

        local boundary = string.match(content_type, ";%s+boundary=(%S+)")
        local new_data = data:gsub(escape_regex(boundary .. "--"), boundary)
        new_data = new_data ..
              "Content-Disposition: form-data; name=\"" .. k:gsub("\"", "%%22") .. "\"\r\n\r\n" ..
              v.value .. "\r\n"
              .. "--" .. boundary .. "--\r\n"
        request.set_body_data(new_data)
]]

end

return _M
